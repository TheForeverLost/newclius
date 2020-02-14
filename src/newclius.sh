
## This function is used to open the config file where external sources are stored
setup(){
    sudo nano /usr/local/bin/newclius/config/config.json
}

exitfunc(){
    echo -e "\033[1m\E[31;40mERROR\033[0m"
    echo $1
    exit    
}


## This function is used to insert the pipeline and repo data into the dynamoDB table for CICD trigger purposes
enterIntoDynamoDB(){
    jq -n \
    --arg cl1 "$1" \
    --arg cl2 "$2" \
    '{
        "codecommitarn": {"S": $cl1 },
        "pipeline": {"S": $cl2 }
    }' > item.json
    table=$(jq -r '.resources | .DynamoMapName' /usr/local/bin/newclius/config/config.json)
    aws dynamodb put-item --table-name $table --item file://item.json
    rm item.json
}

## Creates Code Build Project
createBuildProject(){
    read -p "Enter Build Project Name : " BUILD_PROJECT
    jq -n \
        --arg bn "$BUILD_PROJECT" \
        --arg role "$(jq -r '.roles | .BuildRole' /usr/local/bin/newclius/config/config.json)" \
        '{
            "name": $bn,
            "description": "Build for CodePipeline",
            "source": {
                "type": "CODEPIPELINE",
                "insecureSsl": false
            },
            "artifacts": {
                "type": "CODEPIPELINE"
            },
            "cache": {
                "type": "NO_CACHE"
            },
            "environment": {
                "type": "LINUX_CONTAINER",
                "image": "aws/codebuild/standard:3.0",
                "computeType": "BUILD_GENERAL1_SMALL",
                "environmentVariables": [],
                "privilegedMode": false
            },
            "serviceRole": $role,
            "timeoutInMinutes": 10,
            "tags": [],
            "badgeEnabled": false
        }' > build.json
    aws codebuild create-project --cli-input-json file://build.json 
    rm build.json    
}

## Creates Build Spec file for CodeBuild project to use as reference
createBuildSpec(){
    echo
    echo "- BUILD SPEC GENERATION -"
    echo
    runtime=$1
    shift
    if [ $runtime == nodejs ]
    then
        node -v | grep -q 12 && version=12
        node -v | grep -q 10 && version=10
        node -v | grep -q 8 && version=8
        echo "nodejs version found $version"
        jq -n \
            --arg ver $version \
        '{
            "version": 0.2,
            "phases": {
                "install": {
                "runtime-versions": {
                    "nodejs" : $ver
                    }
                },
                "build": {
                "commands": []
                }
            },
            "artifacts": {
                "type": "zip",
                "files": [
                "template.yml",
                "outputtemplate.yml"
                ]
            }
        }' > buildspec.json
    elif [ $runtime == python ]
    then 
        read -p "Enter runtime env version : " version
        jq -n \
            --arg ver "$version" \
        '{
            "version": 0.2,
            "phases": {
                "install": {
                "runtime-versions": {
                    "python" : $ver
                    }
                },
                "build": {
                "commands": []
                }
            },
            "artifacts": {
                "type": "zip",
                "files": [
                "template.yml",
                "outputtemplate.yml"
                ]
            }
        }' > buildspec.json
    fi
    
    python /usr/local/bin/newclius/config/editjson.py $1 $2 $3 $4 $5 || exitfunc "python error please use version 3.6 and above"
    yq r buildspec.json > $(pwd)/buildspec.yml
    rm buildspec.json
    grep -rl '_S3CODE_' buildspec.yml | xargs sed -i 's;_S3CODE_;'$(jq -r '.resources | .s3CodeStorage' /usr/local/bin/newclius/config/config.json)';g'
    read -p "Press enter to proceed to editting buildspec.yml as per preference" 
    nano $(pwd)/buildspec.yml
}

## Create SAM template for Cloudformation Serverless
createSAMtemplate(){
    echo
    echo "- SAM TEMPLATE GENERATION -"
    echo
    
    read -p "Enter Appliction Description : " Description
    read -p "Enter Handler : " Handler 
    read -p "Enter Runtime Environment ( eg : nodejs12.x ): " Environment
    Execution=$(jq -r '.roles | .LambdaExec' /usr/local/bin/newclius/config/config.json)
    jq -n \
    --arg dsc "$Description" \
    --arg hdr "$Handler" \
    --arg env "$Environment" \
    --arg exec "$Execution" \
    '{
    "AWSTemplateFormatVersion": "2010-09-09",
    "Transform": "AWS::Serverless-2016-10-31",
    "Description": $dsc,
    "Resources": {
        "__ENTER__LAMBDA__FUNCTION__NAME__" : {
            "Type": "AWS::Serverless::Function",
            "Properties": {
                "Handler": $hdr ,
                "Runtime": $env ,
                "Role": $exec ,
                "Events": {
                    "RunApi": {
                        "Type" : "Api" ,
                        "Properties" : {
                            "Path" : "/",
                            "Method" : "ANY"
                        }
                    },
                    "ProxyRunApi": {
                        "Type" : "Api" ,
                        "Properties" : {
                            "Path" : "/{proxy+}",
                            "Method" : "ANY"
                        }
                    }
                }
            }        
        }
    }
    }' > template.json
    yq r template.json > $(pwd)/template.yml
    rm template.json

    echo
    echo "template.yml created"
    echo "remember to put lambda name"
    echo

    read -p "Press enter to proceed to editting template.yml as per preference" 
    nano $(pwd)/template.yml
    grep -q -rl "__ENTER__LAMBDA__FUNCTION__NAME__" template.yml && \
    echo "You forgot to replace function name in SAM template" && exitfunc ""
    
}

## createAdvBuildSpec.yml (self coined term) for the pipeline that pushes code into existing Lambda functions

### This is not a neccessity but to reduce resource utilization the current pipeline uses codebuild even for deployment 
### If codeDeploy is used please update pipeline structure and create neccessary resources for the new pipeline design
createAdvBuildSpec(){
    read -p "Enter lambda function to be updated : " lambda
    read -p "Enter landler for that lambda function : " handler
    read -p "Enter name for zip file where code wilil be stored" zip
    jq -n \
        --arg s3c "$(jq -r '.resources | .s3CodeStorage' /usr/local/bin/newclius/config/config.json)" \
        '{
            "version": 0.2,
            "phases": {
                "install": {
                "runtime-versions": {
                    "nodejs": 10
                },
                "commands": [
                    "aws lambda update-function-configuration --function-name _L_F_N_ --handler _HANDLER_",
                    "aws lambda update-function-code --function-name _L_F_N_ --s3-bucket _S3CODE_ --s3-key _ZIP_FILE_"
                ]
                }
            }
        }' > buildspec.json
    yq r buildspec.json > $(pwd)/advbuildspec.yml
    rm buildspec.json
    grep -rl '_L_F_N_' advbuildspec.yml | xargs sed -i 's;_L_F_N_;'$lambda';g'
    grep -rl '_ZIP_FILE_' advbuildspec.yml | xargs sed -i 's;_ZIP_FILE_;'$zip';g'
    grep -rl '_S3CODE_' advbuildspec.yml | xargs sed -i 's;_S3CODE_;'$(jq -r '.resources | .s3CodeStorage' /usr/local/bin/newclius/config/config.json)';g'
    grep -rl '_HANDLER_' advbuildspec.yml | xargs sed -i 's;_HANDLER_;'$handler';g'
}

## required for codeDeploy
createAppspec(){
    cat /usr/local/bin/newclius/config/appspec.yml > $(pwd)/appspec.yml
    if [ $end = 'f' ]  
    then
    grep -rl 'node' appspec.yml | xargs sed -i 's;node;http;g'
    grep -rl 'reloadServer' appspec.yml | xargs sed -i 's;reloadServer;replaceFolder;g'
    fi
    
    read -p "Press enter to proceed to editting appspec.yml and scripts as per preference" 
    nano appspec.yml
    [ -d $(pwd)/scripts ] || mkdir scripts
    cat /usr/local/bin/newclius/config/install.sh > $(pwd)/scripts/install.sh
    nano $(pwd)/scripts/install.sh
    if [ $end = 'f' ]  
    then
        cat /usr/local/bin/newclius/config/replaceFolder.sh > $(pwd)/scripts/replaceFolder.sh
        nano $(pwd)/scripts/replaceFolder.sh
    else
        cat /usr/local/bin/newclius/config/reloadServer.sh > $(pwd)/scripts/reloadServer.sh
        nano $(pwd)/scripts/reloadServer.sh
    fi
}

## Warning to developer to ensure that the code is executable as an AWS lambda function 
serverlessWarning(){
    echo -e "\033[1m\E[31;40mENSURE that your code should be runnable on AWS Lambda Serverless Application\033[0m"
    read -p "press enter to continue or Ctrl + C to exit"    
}

## PIPELINE TO PUMP CODE TO EXISTING LAMBDA FUNCTION
existingLambdaPipeline(){
    serverlessWarning
    createBuildSpec nodejs 1 1 1
    createBuildProject
    createAdvBuildSpec
    BRANCH=master
    git add .
    git commit -m "CodePipeline"
    git push || exitfunc "git push failed"
    read -p "Enter CodeCommit Repository Name: " REPO
    read -p "Enter Pipeline Name: " PIPELINE
    cat /usr/local/bin/newclius/config/prepipeline3.json > pipeline.json
    PIPELINEROLE=$(jq -r ".roles | .PipelineRole" /usr/local/bin/newclius/config/config.json)
    S3ARTIFACT=$(jq -r ".resources | .s3ArtifactStorage" /usr/local/bin/newclius/config/config.json)
    grep -rl '_PIPELINE_ROLE_' pipeline.json | xargs sed -i 's;_PIPELINE_ROLE_;'$PIPELINEROLE';g'
    grep -rl '_REPO_' pipeline.json | xargs sed -i 's;_REPO_;'$REPO';g'
    grep -rl '_PIPELINE_' pipeline.json | xargs sed -i 's;_PIPELINE_;'$PIPELINE';g'
    grep -rl '_BUILD_' pipeline.json | xargs sed -i 's;_BUILD_;'$BUILD_PROJECT';g'
    grep -rl '_ZIP_FILE_' pipeline.json | xargs sed -i 's;_ZIP_FILE_;'$zip';g'
    S3CODE=$(jq -r '.resources | .s3CodeStorage' /usr/local/bin/newclius/config/config.json)
    grep -rl '_S3CODE_' pipeline.json | xargs sed -i 's;_S3CODE_;'$S3CODE';g'
    grep -rl '_S3ARTIFACT_' pipeline.json | xargs sed -i 's;_S3ARTIFACT_;'$S3ARTIFACT';g'
    POSTBUILD=$(jq -r '.resources | .Serverlessbuild' /usr/local/bin/newclius/config/config.json)
    grep -rl '_POSTBUILD_' pipeline.json | xargs sed -i 's;_POSTBUILD_;'$POSTBUILD';g'
    aws codepipeline create-pipeline --cli-input-json file://pipeline.json > pipeline.json || exitfunc "Pipeline creation failed"
    rm pipeline.json
    
}


## PIPELINE THAT PUSHES CODE TO A NEWLY CREATED LAMBA APPLICATION
newLambdaPipeline(){
    serverlessWarning
    createBuildSpec nodejs 3 1 3 
    createBuildProject
    createSAMtemplate
    BRANCH=master
    git add .
    git commit -m "CodePipeline"
    git push || exitfunc "git push failed"

    read -p "Enter Repository Name : " REPO
    read -p "Enter Build Project Name : " BUILD_PROJECT
    read -p "Enter Pipeline Name : " PIPELINE
    cat /usr/local/bin/newclius/config/prepipeline1.json > pipeline.json
    grep -rl '_REPO_' pipeline.json | xargs sed -i 's;_REPO_;'$REPO';g'
    PIPELINEROLE=$(jq -r ".roles | .PipelineRole" /usr/local/bin/newclius/config/config.json)
    S3ARTIFACT=$(jq -r ".resources | .s3ArtifactStorage" /usr/local/bin/newclius/config/config.json)
    grep -rl '_PIPELINE_ROLE_' pipeline.json | xargs sed -i 's;_PIPELINE_ROLE_;'$PIPELINEROLE';g'
    grep -rl '_S3ARTIFACT_' pipeline.json | xargs sed -i 's;_S3ARTIFACT_;'$S3ARTIFACT';g'
    grep -rl '_BUILD_' pipeline.json | xargs sed -i 's;_BUILD_;'$BUILD_PROJECT';g'
    CFROLE=$(jq -r '.roles | .CloudFormationRole' /usr/local/bin/newclius/config/config.json)
    grep -rl '_PIPELINE_' pipeline.json | xargs sed -i 's;_PIPELINE_;'$PIPELINE';g'
    grep -rl '_CFROLE_' pipeline.json | xargs sed -i 's;_CFROLE_;'$CFROLE';g'
    aws codepipeline create-pipeline --cli-input-json file://pipeline.json > pipeline.json || exitfunc "pipeline creation failed"
    rm pipeline.json
}

## PIPELINE THAT PUSHES CODE INTO S3 BUCKETS FOR STATIC WEB HOSTING
staticWebPipeline(){
    read -p "type 4 for react , type 5 for vue : " framework
    createBuildSpec nodejs $framework 1 $framework
    createBuildProject
    BRANCH=master
    read -p "Enter the codecommit repository name : " REPO
    git add .
    git commit -m "CodePipeline"
    git push || exitfunc "git push failed"
    
    read -p "Enter Repository Name: " REPO
    read -p "Enter Build Project Name" BUILD_PROJECT
    read -p "Enter Pipeline Name: " PIPELINE
    cat /usr/local/bin/newclius/config/prepipeline4.json > pipeline.json
    grep -rl '_REPO_' pipeline.json | xargs sed -i 's;_REPO_;'$REPO';g'
    grep -rl '_BUILD_' pipeline.json | xargs sed -i 's;_BUILD_;'$BUILD_PROJECT';g'
    PIPELINEROLE=$(jq -r ".roles | .PipelineRole" /usr/local/bin/newclius/config/config.json)
    S3ARTIFACT=$(jq -r ".resources | .s3ArtifactStorage" /usr/local/bin/newclius/config/config.json)
    grep -rl '_PIPELINE_ROLE_' pipeline.json | xargs sed -i 's;_PIPELINE_ROLE_;'$PIPELINEROLE';g'
    grep -rl '_S3ARTIFACT_' pipeline.json | xargs sed -i 's;_S3ARTIFACT_;'$S3ARTIFACT';g'
    grep -rl '_PIPELINE_' pipeline.json | xargs sed -i 's;_PIPELINE_;'$PIPELINE';g'
    
    aws codepipeline create-pipeline --cli-input-json file://pipeline.json > pipeline.json || exitfunc "pipeline creation failed"
    rm pipeline.json
}

# Function to setup codedeploy agent in ec2 instances
setupCodeDeployAgent(){
    read -p "enter path to pem file $1.pem : " p
    scp -i $p/$1.pem /usr/local/bin/newclius/config/codeDeploySetup.sh ubuntu@$2:~  && \
    echo "" && \
    echo -e "\033[1m\E[33;40mAttention\033[0m" && \
    echo "you'll be connected to your EC2 instance" && \
    echo "go to the /home/ubuntu and locate the codeDeploySetup.sh and run it" && \
    read -p "press Enter to continue" && \
    ssh -i $1.pem ubuntu@$2 || \
    echo "Error occured please make sure the EC2 instance is running and online and you have the pem file" && \
    exit
}

# Function to create the codedeploy groups
createCodeDeploy(){
    read -p "Enter EC2 test instance name : " NAME1
    read -p "Enter EC2 prod instance name : " NAME2
    read -p "give tag name to be attached to EC2 instance : " TAG
    aws ec2 describe-instances --filter "Name=tag-value,Values=$NAME1" > ec2.json && \
    pINSTANCE_ID=$(jq -r ".Reservations | .[] | .Instances | .[] | .InstanceId" ec2.json) || exitfunc "instance doesnt exist"
    setupCodeDeployAgent $(jq -r ".Reservations | .[] | .Instances | .[] | .KeyName" ec2.json) $(jq -r ".Reservations | .[] | .Instances | .[] | .PublicDnsName" ec2.json)
    aws ec2 create-tags \
    --resources $pINSTANCE_ID --tags Key=$TAG,Value=prod 
     aws ec2 associate-iam-instance-profile \
     --instance-id i-05f2e03602eda8157 \
     --iam-instance-profile Name=$(jq -r '.resources | .EC2IAMProfile' /usr/local/bin/newclius/config/config.json) || exitfunc "IAM instance profile couldnt be added"
    aws ec2 describe-instances --filter "Name=tag-value,Values=$NAME2" > ec2.json && \
    dINSTANCE_ID=$(jq -r ".Reservations | .[] | .Instances | .[] | .InstanceId" ec2.json) || exitfunc "instance doesnt exist"
    setupCodeDeployAgent $(jq -r ".Reservations | .[] | .Instances | .[] | .KeyName" ec2.json) $(jq -r ".Reservations | .[] | .Instances | .[] | .PublicDnsName" ec2.json)
    aws ec2 create-tags \
    --resources $dINSTANCE_ID --tags Key=$TAG,Value=dev 
     aws ec2 associate-iam-instance-profile \
     --instance-id i-05f2e03602eda8157 \
     --iam-instance-profile Name=$(jq -r '.resources | .EC2IAMProfile' /usr/local/bin/newclius/config/config.json) || exitfunc "IAM instance profile couldnt be added"
    rm ec2.json
    read -p "Enter name for deployment application : " APPNAME
    cat /usr/local/bin/newclius/config/CodeDeployApplication.json > deployapplication.json
    grep -rl '_APP_' deployapplication.json | xargs sed -i 's;_APP_;'$APPNAME';g'
    aws deploy create-application --cli-input-json file://deployapplication.json || exitfunc "CodeDeploy Application create failed"
    cat /usr/local/bin/newclius/config/CodeDeployGroup.json > /deploygroup.json
    grep -rl '_APP_' deploygroup.json | xargs sed -i 's;_APP_;'$APPNAME';g'
    grep -rl '_TAG_' deploygroup.json | xargs sed -i 's;_TAG_;'$TAG';g'
    aws deploy create-deployment-group --cli-input-json file://deploygroup.json || exitfunc "CodeDeploy group create failed"
    grep -rl 'prod' deploygroup.json | xargs sed -i 's;prod;dev;g'
    aws deploy create-deployment-group --cli-input-json file://deploygroup.json || exitfunc "CodeDeploy group create failed"
    rm deploygroup.json
    rm deployapplication.json
}

## PIPELINE THAT PUSHES CODE ONTO A EC2 INSTANCE
EC2Pipeline(){
    read -p "frontend or backend (f/b) : " end
    if [ $end = 'f' ]  
    then
        read -p "type 4 for react , type 5 for vue : " framework
        createBuildSpec nodejs 2 2 2 $framework
    else
        createBuildSpec nodejs 1 1 1
    fi
    createBuildProject
    createAppspec
    createCodeDeploy
    BRANCH=master
    git add .
    git commit -m "CodePipeline"
    git push || exitfunc "git push failed"
    
    read -p "Enter Repository Name: " REPO
    read -p "Enter Build Project Name" BUILD_PROJECT
    read -p "Enter Pipeline Name: " PIPELINE
    cat /usr/local/bin/newclius/config/prepipeline2.json > pipeline.json
    grep -rl '_REPO_' pipeline.json | xargs sed -i 's;_REPO_;'$REPO';g'
    PIPELINEROLE=$(jq -r ".roles | .PipelineRole" /usr/local/bin/newclius/config/config.json)
    S3ARTIFACT=$(jq -r ".resources | .s3ArtifactStorage" /usr/local/bin/newclius/config/config.json)
    grep -rl '_PIPELINE_ROLE_' pipeline.json | xargs sed -i 's;_PIPELINE_ROLE_;'$PIPELINEROLE';g'
    grep -rl '_S3ARTIFACT_' pipeline.json | xargs sed -i 's;_S3ARTIFACT_;'$S3ARTIFACT';g'
    grep -rl '_BUILD_' pipeline.json | xargs sed -i 's;_BUILD_;'$BUILD_PROJECT';g'
    grep -rl '_APPL_' pipeline.json | xargs sed -i 's;_APPL_;'$APPNAME';g'
    grep -rl '_PIPELINE_' pipeline.json | xargs sed -i 's;_PIPELINE_;'$PIPELINE';g'
    grep -rl '_GROUP_' pipeline.json | xargs sed -i 's;_GROUP_;'$APPNAME'-dev;g'
    aws codepipeline create-pipeline --cli-input-json file://pipeline.json > pipeline.json || exitfunc "pipeline creation failed"
    rm pipeline.json
}

## Generates pretty help document
usage(){
    echo ""
    echo -e "\033[1mNEWCLIUS\033[0m"
    echo ""
    echo "      Command line tool to simplify pipeline creation "
    echo "      Use inside directory connected to CodeCommit"
    echo ""
    echo -e "\033[1m\E[36;40mOPTIONS\033[0m"
    tput sgr0
    echo ""
    echo -e "\t\033[1m\E[32;40m-h | help\033[0m"
    tput sgr0
    echo ""
    echo "        Opens this usage document for user reference"
    echo ""
    echo ""
    echo -e "\t\033[1m\E[32;40msetup\033[0m"
    tput sgr0
    echo ""
    echo "        Setup the AWS resources and roles that will be used in pipeline"
    echo "        generation"
    echo ""
    echo ""
    echo -e "\t\033[1m\E[32;40mReadyForProd\033[0m"
    tput sgr0
    echo ""
    echo "        switches EC2 pipeline from test to prod "
    echo ""
    echo "        usage : newclius ReadyForProd"
    echo ""
    echo ""
    echo -e "\t\033[1m\E[33;40mEC2\033[0m"
    tput sgr0
    echo ""
    echo "        Creates pipeline for applications running in AWS EC2 instances "
    echo "        The pipeline is directed to test EC2 server but can be redirected "
    echo "        to production EC2 server using the ReadyForProd command"
    echo "        includes the following :"
    echo ""
    echo "            ~ Creation of Buildspec file"
    echo "            ~ Creation of Appspec file"
    echo "            ~ Creation of Scripts"
    echo "            ~ External configuration of EC2 for CodeDeploy"
    echo "            ~ Creation of CodeBuild Project"
    echo "            ~ Creation of Pipeline and CodeDeploy application"
    echo ""
    echo "        usage : newclius EC2"
    echo ""
    echo ""
    echo -e "\t\033[1m\E[33;40mnewLambda\033[0m"
    tput sgr0
    echo ""
    echo "        Creates a serverless application which includes a AWS Lambda "
    echo "        function and API gateway using CloudFormation"
    echo "        includes the following : "
    echo ""
    echo "            ~ Creation of Buildspec file"
    echo "            ~ Creation of SAM template"
    echo "            ~ Creation of CodeBuild Project"
    echo "            ~ Creation of Pipeline"
    echo ""
    echo "        usage : newclius newLambda"
    echo ""
    echo ""
    echo -e "\t\033[1m\E[33;40mexistingLambda\033[0m"
    tput sgr0
    echo ""
    echo "        Connects a repository to a existing serverless function without "
    echo "        using CodeDeploy"
    echo "        includes the following :"
    echo ""
    echo "            ~ Creation of Buildspec file"
    echo "            ~ Creation of advBuildspec file (script to update lambda code)"
    echo "            ~ Creation of CodeBuild Project"
    echo "            ~ Creation of Pipeline"
    echo ""
    echo "        usage : newclius existingLambda"
    echo ""
    echo ""
    echo -e "\t\033[1m\E[33;40mstaticweb\033[0m"
    tput sgr0
    echo ""
    echo "        Connects a repository to a existing s3 bucket with static web hosting "
    echo "        enabled"
    echo "        includes the following :"
    echo ""
    echo "            ~ Creation of Buildspec"
    echo "            ~ Creation of CodeBuild Project"
    echo "            ~ Creation of Pipeline"
    echo ""
    echo "        usage : newclius staticweb"
    echo -e "\033[1m\E[32;40mWarning\033[0m"
    tput sgr0
    echo ""
    echo "  before using newclius, a few things to be kept in mind"
    echo "      1. Newclius is not covering for your cost for aws resources"
    echo "      2. It is recommended you have some prior knowledge of AWS CodeSuite"
    echo "          https://docs.aws.amazon.com/ec2/?id=docs_gateway"
    echo "          https://docs.aws.amazon.com/s3/?id=docs_gateway"
    echo "          https://docs.aws.amazon.com/apigateway/?id=docs_gateway"
    echo "          https://docs.aws.amazon.com/lambda/?id=docs_gateway"
    echo "          https://docs.aws.amazon.com/codebuild/?id=docs_gateway"
    echo "          https://docs.aws.amazon.com/codedeploy/?id=docs_gateway"
    echo "          https://docs.aws.amazon.com/codepipeline/?id=docs_gateway"
    echo "          https://docs.aws.amazon.com/iam/?id=docs_gateway"
    

}

error(){
    echo "  $1 is an invalid command refer usage documentation "
    echo "  newclius -h | newclius help"
}

switch(){
    read -p "enter pipeline name : " PIPELINENAME
    aws codepipeline get-pipeline --name $PIPELINENAME > pipe.json || exitfunc "Pipeline not found"
    echo '{ "pipeline" : '$(jq -r ".pipeline" pipe.json)' }' > pipe.json
    jq -r '.pipeline | .stages[2] | .actions[0] | .configuration | .DeploymentGroupName'  pipe.json | grep -- -prod && echo "Already in prod" && exit
    grep -rl -- '-dev' pipe.json | xargs sed -i 's/-dev/-prod/g'
    aws codepipeline update-pipeline --cli-input-json file://pipe.json || exitfunc "Pipeline couldnt be upgraded"
    rm pipe.json
}

removeFromGit(){
    echo "pipe.json" >> .gitignore
    echo "pipeline.json" >> .gitignore
    echo "buildspec.json" >> .gitignore
    echo "template.json" >> .gitignore
    echo "EC2.json" >> .gitignore
    echo "item.json" >> .gitignore
    echo "repodata.json" >> .gitignore
    echo "deployapplication.json" >> .gitignore 
    echo "deploygroup.json" >> .gitignore
}

if [ "$1" = "" ]
then
    usage
fi
[ -e .gitignore ] && removeFromGit
while [ "$1" != "" ]; do
    case $1 in
        EC2 )                   EC2Pipeline
                                exit
                                ;;
        ReadyForProd )    switch
                                exit
                                ;;
        staticweb )             staticWebPipeline
                                exit
                                ;;
        newLambda )             newLambdaPipeline
                                exit
                                ;;
        existingLambda )        existingLambdaPipeline
                                exit
                                ;;
        setup )                 setup
                                exit
                                ;;
        -h | help )           usage
                                exit
                                ;;
        * )                     error $1
                                exit
                                ;;
    esac
    shift
done
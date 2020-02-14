# NEWCLIUS

**Work in progress**

Maded Due to unavailability of AWS codestar in the ap-south-1 region as of 14/02/20 
newclius Command line tool will help you make aws codepipelines to connect your codecommit repos to wherever they are being deployed 

**Version** `0.1`

### Prerequisites

- Understanding of AWS 
- AWS account with accecss to the following : EC2 , S3 , lambda , apigateway , cloudformation , codestar , codepipeline , codebuild , codecommit , IAM roles and policies , codedeploy

### Dependencies 
- awscli 1
- python 3.6 or above
- yq
- jq

## Installation

Clone repository 
```bash
git clone https://git-codecommit.ap-south-1.amazonaws.com/v1/repos/newclius 
```
Switch current directory to the directory where newclius repository has been cloned and run the setup script
```bash
./setup 
```
After creating the resources that are to be shared between (future version will do that automatically)
```bash
newclius setup
```
run newclius help command to get the usage document 
```bash
newclius help
```

## Information

before using newclius, a few things to be kept in mind
    1. Newclius is not covering for your cost for aws resources
    2. It is recommended you have some prior knowledge of AWS CodeSuite
        - https://docs.aws.amazon.com/ec2/?id=docs_gateway
        - https://docs.aws.amazon.com/s3/?id=docs_gateway
        - https://docs.aws.amazon.com/apigateway/?id=docs_gateway
        - https://docs.aws.amazon.com/lambda/?id=docs_gateway
        - https://docs.aws.amazon.com/codebuild/?id=docs_gateway
        - https://docs.aws.amazon.com/codedeploy/?id=docs_gateway
        - https://docs.aws.amazon.com/codepipeline/?id=docs_gateway
        - https://docs.aws.amazon.com/iam/?id=docs_gateway

### features upcoming in future updates

- support for github repos
- Automatic creation of shared resources
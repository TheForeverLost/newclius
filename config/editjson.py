import json
import sys
opt = int(sys.argv[1])
commands = {
    1 : [
        "npm i"
    ],
    2 : [
        "npm i",
        "npm run build"
    ],
    3 : [
        "npm i",
        "aws cloudformation package --template-file template.yml --s3-bucket _S3CODE_ --output-template-file outputtemplate.yml"
    ],
    4 : [
        "npm i", 
        "npm run build",
        "aws s3 sync build/ s3://_B_N_A_ --delete"
    ],
    5 : [
        "npm i", 
        "npm run dist",
        "aws s3 sync dist/ s3://_B_N_A_ --delete"
    ]
}
artifacts = {
    1:[
        "./**/*"
        ],
    2:[
        "scripts/*",
        "appspec.yml"
    ],
    3:[
        "template.yml",
        "outputtemplate.yml"
        ],
    4:[
        "build/**/*"
        ],
    5:[
        "dist/**/*"
        ],
}
with open('buildspec.json') as f:
  data = json.load(f)
# Output: {'name': 'Bob', 'languages': ['English', 'Fench']}
  data["phases"]["build"]["commands"] = commands[opt]
  artifacts_f = []
  i = 0
  for i in range(int(sys.argv[2])) :
      artifacts_f = artifacts_f + artifacts[(int(sys.argv[3+i]))] 
  data["artifacts"]["files"] = artifacts_f

with open('buildspec.json','w') as f:
    json.dump(data , f)
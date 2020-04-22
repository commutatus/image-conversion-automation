#!/bin/sh
# This is where the lambda compressed file gets uploaded
lambda_s3_bucket='lambda-image-conversion/image-conversion-test/'

if [ ! -d "./cloudfront-lambda-image-optimization" ]; then
  git clone git@github.com:commutatus/cloudfront-lambda-image-optimization.git
else
  echo 'Moving into directory'
  cd cloudfront-lambda-image-optimization
fi
# echo 'Building the docker...'
# docker build --tag lambci/lambda:build-nodejs10.0 .
# echo 'Installing necessary tools...'
# docker run --rm --volume ${PWD}/lambda/origin-response-function:/build lambci/lambda:build-nodejs10.0 /bin/bash -c "source ~/.bashrc; npm init -f -y; npm install sharp --save; npm install querystring --save; npm install --only=prod"
# docker run --rm --volume ${PWD}/lambda/viewer-request-function:/build lambci/lambda:build-nodejs10.0 /bin/bash -c "source ~/.bashrc; npm init -f -y; npm install querystring --save; npm install path --save; npm install useragent --save; npm install yamlparser; npm install --only=prod"
# echo 'Building the deployment packages...'
# mkdir -p dist && cd lambda/origin-response-function && zip -FS -q -r ../../dist/origin-response-function.zip * && cd ../..
# mkdir -p dist && cd lambda/viewer-request-function && zip -FS -q -r ../../dist/viewer-request-function.zip * && cd ../..
# echo 'Copying deployment packages to S3'
#
# aws s3 cp dist/origin-response-function.zip s3://${lambda_s3_bucket}
aws s3 cp dist/viewer-request-function.zip s3://${lambda_s3_bucket}
echo 'Deploying the lambda function'
aws cloudformation deploy --template-file aws-sam-lambda-edge-webp.yaml --stack-name webp-conversion --capabilities CAPABILITY_NAMED_IAM --region us-east-1

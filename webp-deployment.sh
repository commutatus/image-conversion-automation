#!/bin/sh
# This is where the lambda compressed file gets uploaded

helpFunction()
{
   echo ""
   echo "Usage: $0 -lambda_s3_bucket BUCKET-NAME -project_s3_bucket BUCKET-NAME -cloudformation_stack_name STACK-NAME"
   echo ""
   echo "\t-lambda_s3_bucket - \t Bucket to store compiled lambda function."
   echo "\t-project_s3_bucket - \t This is your project bucket, will get linked with cloudfront."
   echo "\t-cloudformation_stack_name - \t Cloud formation deployment stack name."
   exit 1 # Exit script after printing help
}

for ARGUMENT in "$@"
do
  KEY=$(echo $ARGUMENT | cut -f1 -d=)
  VALUE=$(echo $ARGUMENT | cut -f2 -d=)
  case "$KEY" in
          lambda_s3_bucket)              lambda_s3_bucket=${VALUE} ;;
          project_s3_bucket)    project_s3_bucket=${VALUE} ;;
          cloudformation_stack_name)     cloudformation_stack_name=${VALUE};;
          *)
  esac
done

# Print helpFunction in case parameters are empty
if [ -z "$lambda_s3_bucket" ] || [ -z "$project_s3_bucket" ] || [ -z "$cloudformation_stack_name" ]
then
   echo "Some or all of the parameters are empty";
   helpFunction
fi

origin_response_function="${cloudformation_stack_name}OriginResponseFunction"
viewer_request_function="${cloudformation_stack_name}ViewerRequestFunction"

if [ ! -d "./cloudfront-lambda-image-optimization" ]; then
  git clone git@github.com:commutatus/cloudfront-lambda-image-optimization.git
fi
echo 'Moving into directory'
cd cloudfront-lambda-image-optimization

setup_docker()
{
  echo 'Building the docker...'
  docker build --tag lambci/lambda:build-nodejs10.0 .
  echo 'Installing necessary tools...'
  docker run --rm --volume ${PWD}/lambda/origin-response-function:/build lambci/lambda:build-nodejs10.0 /bin/bash -c "source ~/.bashrc; npm init -f -y; npm install sharp --save; npm install querystring --save; npm install --only=prod"
  docker run --rm --volume ${PWD}/lambda/viewer-request-function:/build lambci/lambda:build-nodejs10.0 /bin/bash -c "source ~/.bashrc; npm init -f -y; npm install querystring --save; npm install path --save; npm install useragent --save; npm install yamlparser; npm install --only=prod"
}

cloudformation_rename_bucket_name()
{
  echo 'Cloudformation bucket renaming...'
  aws_sam_file="aws-sam-lambda-edge-webp.yaml"
  aws_sam_outfile="aws-sam-lambda-edge-webp-new.yaml"
  while IFS= read line
  do
    if [[ $line == *"lambda-compressed-file-storage"* ]]; then
      echo "${line/lambda-compressed-file-storage/$lambda_s3_bucket}">> "$aws_sam_outfile"
    elif [[ $line == *"OriginResponseFunction"* ]]; then
      echo "${line/OriginResponseFunction/$origin_response_function}">> "$aws_sam_outfile"
    elif [[ $line == *"ViewerRequestFunction"* ]]; then
      echo "${line/ViewerRequestFunction/$viewer_request_function}">> "$aws_sam_outfile"
    else
      echo "${line}">> "$aws_sam_outfile"
    fi
  done < "$aws_sam_file"
  origin_handler_file="lambda/origin-response-function/handler.js"
  origin_handler_outfile="lambda/origin-response-function/handler_updated.js"
  while IFS= read line
  do
    if [[ $line == *"bucket-name"* ]]; then
      echo "${line/bucket-name/$project_s3_bucket}" >> "$origin_handler_outfile"
    else
      echo "${line}" >> "$origin_handler_outfile"
    fi
  done < "$origin_handler_file"
  mv lambda/origin-response-function/handler_updated.js lambda/origin-response-function/handler.js
}

compile_lambda_and_push()
{
  echo 'Building the deployment packages...'
  mkdir -p dist && cd lambda/origin-response-function && zip -FS -q -r ../../dist/origin-response-function.zip * && cd ../..
  mkdir -p dist && cd lambda/viewer-request-function && zip -FS -q -r ../../dist/viewer-request-function.zip * && cd ../..
  echo 'Copying deployment packages to S3'

  aws s3 cp dist/origin-response-function.zip s3://${lambda_s3_bucket}/origin-response-function.zip
  aws s3 cp dist/viewer-request-function.zip s3://${lambda_s3_bucket}/viewer-request-function.zip
  echo 'Deploying the lambda function'
}

deploy_lambda_function()
{
  echo "Deploying cloudformation template."
  cloudformation_creation=`aws cloudformation deploy --template-file aws-sam-lambda-edge-webp-new.yaml --stack-name ${cloudformation_stack_name} --capabilities CAPABILITY_NAMED_IAM --region us-east-1`
}

update_bucket_policy()
{
  echo "Update bucket policy."
  cd ..
  rm my_bucket_policy.json
  lambda_function=`aws lambda get-function --function-name ${origin_response_function} --region us-east-1`
  iam_arn=`echo $lambda_function | jq '.Configuration.Role'`
  temp_iam_arn="${iam_arn%\"}"
  temp_iam_arn="${temp_iam_arn#\"}"
  echo $temp_iam_arn
  default_policy='default_bucket_policy.json'
  updated_bucket_policy='my_bucket_policy.json'
  while IFS= read line
  do
    if [[ $line == *"bucket-name"* ]]; then
      echo "${line/bucket-name/$project_s3_bucket}">> "$updated_bucket_policy"
    else
      echo "${line/lambda-role/$temp_iam_arn}">> "$updated_bucket_policy"
    fi
  done < "$default_policy"
  update_bucket_acl=`aws s3api put-bucket-acl --bucket ${project_s3_bucket} --acl public-read`
  update_bucket_policy=`aws s3api put-bucket-policy --bucket ${project_s3_bucket} --policy file://my_bucket_policy.json`
}

create_cloufront_distribution()
{
  echo "Create cloudfront distribution."
  origin_response_lambda_version_list=`aws lambda list-versions-by-function --function-name ${origin_response_function} --region us-east-1`
  origin_response_arn=`echo $origin_response_lambda_version_list |  jq '.Versions[-1].FunctionArn'`
  temp_origin_response_arn="${origin_response_arn%\"}"
  temp_origin_response_arn="${temp_origin_response_arn#\"}"
  echo $temp_origin_response_arn

  viewer_request_lambda_version_list=`aws lambda list-versions-by-function --function-name ${viewer_request_function} --region us-east-1`
  viewer_request_arn=`echo $viewer_request_lambda_version_list |  jq '.Versions[-1].FunctionArn'`
  temp_viewer_request_arn="${viewer_request_arn%\"}"
  temp_viewer_request_arn="${temp_viewer_request_arn#\"}"
  echo $temp_viewer_request_arn


  cf_distribution_file='default_distribution_create_config.json'
  cf_distribution_outfile='my_distribution_create_config.json'
  while IFS= read line
  do
    if [[ $line == *"bucket-name"* ]]; then
      echo "${line/bucket-name/$project_s3_bucket}">> "$cf_distribution_outfile"
    elif [[ $line == *"origin-response-arn"* ]]; then
      echo "${line/origin-response-arn/$temp_origin_response_arn}">> "$cf_distribution_outfile"
    elif [[ $line == *"viewer-request-arn"* ]]; then
      echo "${line/viewer-request-arn/$temp_viewer_request_arn}">> "$cf_distribution_outfile"
    else
      echo "${line}" >> "$cf_distribution_outfile"
    fi
  done < "$cf_distribution_file"
  create-distribution=`aws cloudfront create-distribution --distribution-config file://my_distribution_create_config.json`
}


setup_docker
cloudformation_rename_bucket_name
compile_lambda_and_push
deploy_lambda_function
update_bucket_policy
create_cloufront_distribution

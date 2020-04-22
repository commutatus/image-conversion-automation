# Webp Deployment Automation

The project will help you with the deployment of various AWS services, which finally helps you converting the JPEG image into the webp file.

It helps you setup the following tools and services

- Setup docker container
- Update the S3 Permission policies
- Setup the cloudformation template. Which deploys the lambda function, creates IAM role, AWS logs.
- Create the cloudfront distribution
- Upadte the cloudfront distribution with the lambda function ARN.


**Deployment**

- To run this project :
- `./webp_deployment_automation.rb create`

We can also load the ruby script in the interactive ruby session.

- `require './webp_deployment_automation.rb'`
- `lambda_compressed_file_s3_storage='LAMBDA_FILE_STORAGE_BUCKET'`
- `cloudfront_s3_bucket = 'YOUR_S3_IMAGE_BUCKET'`
- `cloudformation_stack_name = 'CLOUDFORMATION_STACK_NAME'`
- `webp_deploy = WebpDeploymentAutomation.new(lambda_compressed_file_s3_storage, cloudfront_s3_bucket, cloudformation_stack_name)`
- Then call the methods from the ruby file.

---

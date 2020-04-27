# Webp Deployment Automation

The project will help you with the deployment of various AWS services, which finally helps you automatically converting JPEG images into WebP on the fly (and storing a cache). It requires an existing S3 bucket. It also supports dimension queries to send the output image in a specific file size.

Usage of next-gen image formats can speed up your site and improve usability and SEO. Read an implementation blog [here](https://medium.com/commutatus/how-we-improved-the-performance-of-an-e-commerce-site-using-next-gen-image-formats-8bcff1bf5b19). 

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


We can also deploy the same using the shell script.

```
./webp-deployment.sh lambda_s3_bucket=lambda-image-conversion/image-conversion-test project_s3_bucket=image-webp-conversion-test4 cloudformation_stack_name=CloudformationStackName
```

**Usage**

- Once deployed you can send requests to the Cloudfront distribution and if the user agent allows WebP, the response will contain a webP version of the JPG/PNG image requested. 
- The distribution will also return images of a specific dimension, you can append `?d=100x100`to the URL

**References**

- This script automates an item in the efficiency section of Commutatus' Awesome Framework. You can find all background details [here](https://awesome.commutatus.com/domains/engineering/efficient/cloudfront-image-conversion.html). 


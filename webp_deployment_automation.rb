#!/usr/bin/ruby
require 'json'


class WebpDeploymentAutomation
  attr_reader :lambda_compressed_file_s3_storage, :cloudfront_s3_bucket, :cloudformation_stack_name, :origin_response_function, :viewer_request_function

  def initialize(lambda_compressed_file_s3_storage, cloudfront_s3_bucket, cloudformation_stack_name)
    @lambda_compressed_file_s3_storage = lambda_compressed_file_s3_storage
    @cloudfront_s3_bucket = cloudfront_s3_bucket
    @cloudformation_stack_name = cloudformation_stack_name
    @origin_response_function = cloudformation_stack_name.split('-').map(&:capitalize).join + 'OriginResponseFunction'
    @viewer_request_function = cloudformation_stack_name.split('-').map(&:capitalize).join + 'ViewerRequestFunction'
  end

  def setup_docker
    if File.directory?('cloudfront-lambda-image-optimization')
      system("echo 'Moving into directory'")
      Dir.chdir 'cloudfront-lambda-image-optimization'
      system('echo *')
    else
      `git clone git@github.com:commutatus/cloudfront-lambda-image-optimization.git`
      Dir.chdir 'cloudfront-lambda-image-optimization'
    end
    system("echo 'Building the docker...'")
    system("docker build --tag lambci/lambda:build-nodejs10.0 .")
    system("echo 'Installing necessary tools...'")
    system('docker run --rm --volume ${PWD}/lambda/origin-response-function:/build lambci/lambda:build-nodejs10.0 /bin/bash -c "source ~/.bashrc; npm init -f -y; npm install sharp --save; npm install querystring --save; npm install --only=prod"')
    system('docker run --rm --volume ${PWD}/lambda/viewer-request-function:/build lambci/lambda:build-nodejs10.0 /bin/bash -c "source ~/.bashrc; npm init -f -y; npm install querystring --save; npm install path --save; npm install useragent --save; npm install yamlparser; npm install --only=prod"')
  end

  def  cloudformation_rename_bucket_name
    cloudformation_yaml_config = File.read('aws-sam-lambda-edge-webp.yaml')
    replace = cloudformation_yaml_config.gsub(/lambda-compressed-file-storage/, lambda_compressed_file_s3_storage)
    replace = replace.gsub(/OriginResponseFunction/, origin_response_function)
    replace = replace.gsub(/ViewerRequestFunction/, viewer_request_function)
    File.open('aws-sam-lambda-edge-webp.yaml', "w") {|file| file.puts replace}
    origin_reponse_file = File.read('lambda/origin-response-function/handler.js')
    replace = origin_reponse_file.gsub(/bucket-name/, cloudfront_s3_bucket)
    File.open('lambda/origin-response-function/handler.js', "w") {|file| file.puts replace}
  end

  def compile_lambda_and_push
    system("echo 'Building the deployment packages...'")
    system("mkdir -p dist && cd lambda/origin-response-function && zip -FS -q -r ../../dist/origin-response-function.zip * && cd ../..")
    system("mkdir -p dist && cd lambda/viewer-request-function && zip -FS -q -r ../../dist/viewer-request-function.zip * && cd ../..")
    system("echo 'Copying deployment packages to S3'")

    system("aws s3 cp dist/origin-response-function.zip s3://#{lambda_compressed_file_s3_storage}/")
    system("aws s3 cp dist/viewer-request-function.zip s3://#{lambda_compressed_file_s3_storage}/")
    system("echo 'Deploying the lambda function'")
  end

  def deploy_lambda_function
    system("aws cloudformation deploy --template-file aws-sam-lambda-edge-webp.yaml --stack-name #{self.cloudformation_stack_name} --capabilities CAPABILITY_NAMED_IAM --region us-east-1")
  end

  def update_bucket_policy
    function = `aws lambda get-function --function-name #{self.origin_response_function} --region us-east-1`
    parsed_function = JSON.parse(function)
    iam_arn = parsed_function['Configuration']['Role']
    default_policy = File.read('../default_bucket_policy.json')
    replace = default_policy.gsub(/bucket-name/, cloudfront_s3_bucket)
    replace = replace.gsub(/lambda-role/, iam_arn)
    File.open('my_bucket_policy.json', "w") {|file| file.puts replace}
    system("aws s3api put-bucket-acl --bucket #{cloudfront_s3_bucket} --acl public-read")
    system("aws s3api put-bucket-policy --bucket #{cloudfront_s3_bucket} --policy file://my_bucket_policy.json")
  end

  def get_latest_lambda_arn
    origin_response_lambda_version_list = `aws lambda list-versions-by-function --function-name #{self.origin_response_function} --region us-east-1`
    origin_response_parsed_json = JSON.parse(origin_response_lambda_version_list)
    @origin_response_function_arn = origin_response_parsed_json["Versions"][-1]['FunctionArn']
    puts @origin_response_function_arn

    viewer_request_lambda_version_list = `aws lambda list-versions-by-function --function-name #{self.viewer_request_function} --region us-east-1`
    viewer_request_parsed_json = JSON.parse(viewer_request_lambda_version_list)
    @viewer_request_function_arn = viewer_request_parsed_json["Versions"][-1]['FunctionArn']
    puts @viewer_request_function_arn
  end


  def create_cloufront_distribution
    get_latest_lambda_arn
    Dir.chdir('..')
    distribution_create_config = File.read('default_distribution_create_config.json')
    replace = distribution_create_config.gsub(/bucket-name/, cloudfront_s3_bucket)
    replace = replace.gsub(/origin-response-arn/, @origin_response_function_arn)
    replace = replace.gsub(/viewer-request-arn/, @viewer_request_function_arn)
    File.open('my_distribution_create_config.json', "w") {|file| file.puts replace}
    `aws cloudfront create-distribution --distribution-config file://my_distribution_create_config.json`
  end


  def update_cloud_front_distribution
    get_distribution = `aws cloudfront get-distribution --id E88SR8T7SZ9ER`
    parsed_distribution_data = JSON.parse(get_distribution)

    File.open("distribution_information.json","w") do |f|
      f.write(get_distribution)
    end

    File.open("distribution_config_information.json","w") do |f|
      f.write(JSON.pretty_generate(parsed_distribution_data["Distribution"]["DistributionConfig"]))
    end

    etag = parsed_distribution_data['ETag']

    distribution_status = 'In progress'
    until distribution_status == 'Deployed'
      sleep 300
      get_distribution = `aws cloudfront get-distribution --id E88SR8T7SZ9ER`
      parsed_distribution_data = JSON.parse(get_distribution)
      distribution_status = parsed_distribution_data['Distribution']['Status']
    end
    system("aws cloudfront update-distribution --id E88SR8T7SZ9ER --distribution-config file://distribution_config_information.json --if-match #{etag}")
  end

end

# This is where the lambda compressed file gets uploaded
lambda_compressed_file_s3_storage='lambda-image-conversion/image-conversion-test'
cloudfront_s3_bucket = 'image-webp-conversion-test4'
cloudformation_stack_name = 'image-webp-conversion'

webp_deploy = WebpDeploymentAutomation.new(lambda_compressed_file_s3_storage, cloudfront_s3_bucket, cloudformation_stack_name)
if ARGV[0] == "create"
  webp_deploy.setup_docker
  webp_deploy.cloudformation_rename_bucket_name
  webp_deploy.compile_lambda_and_push
  webp_deploy.deploy_lambda_function
  webp_deploy.update_bucket_policy
  webp_deploy.create_cloufront_distribution
elsif ARGV[0] == "update"
  webp_deploy.update_cloud_front_distribution
end

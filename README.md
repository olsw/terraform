### Terraform

Site release is managed by terraform.

Environment variables required: AWS_SECRET_ACCESS_KEY and AWS_ACCESS_KEY_ID for a suitable AWS User

Change the site_domain variable if you are testing on an alternative site

Terraform will:

 * Create S3 bucket with permissions for public read
 * Create S3 bucket for logging
 * Create and validate ssl certificate using ACM
 * Create cloudfront distribution
 * Create Route53 records for $site_domain and www.$site_domain

New site creation requires:

```
terraform init
terraform plan (if required)
terraform apply
```

 ### Web Site

Very basic react site in the test-site folder. This can be deployed to the relevant S3 bucket using 
```npm run deploy```

If testing on a new site the line in package.json: 

```"deploy": "aws s3 sync build/ s3://testsiteserver.com"```

 will need to be updated with new relevant s3 bucket

 Current site is available at https://testsiteserver.com
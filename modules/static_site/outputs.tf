output "bucket_name" {
  description = "Name of the private S3 origin bucket."
  value       = aws_s3_bucket.site.id
}

output "bucket_arn" {
  description = "ARN of the private S3 origin bucket."
  value       = aws_s3_bucket.site.arn
}

output "distribution_id" {
  description = "CloudFront distribution ID, needed to create cache invalidations."
  value       = aws_cloudfront_distribution.site.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = aws_cloudfront_distribution.site.arn
}

output "domain_name" {
  description = "CloudFront domain name serving the site."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "site_url" {
  description = "Public HTTPS URL of the deployed site."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

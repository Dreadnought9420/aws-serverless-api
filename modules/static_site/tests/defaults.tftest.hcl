# Unit tests for the static_site module.
#
# The aws provider is mocked, so these runs create nothing, cost nothing and
# need no credentials. Run from this module's directory:
#
#   terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix            = "unit-test"
  bucket_suffix          = "123456789012"
  content_dir            = "./tests/fixtures/site"
  api_origin_domain_name = "abc123.execute-api.eu-west-1.amazonaws.com"
}

run "origin_bucket_is_private" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.site.block_public_acls,
      aws_s3_bucket_public_access_block.site.block_public_policy,
      aws_s3_bucket_public_access_block.site.ignore_public_acls,
      aws_s3_bucket_public_access_block.site.restrict_public_buckets,
    ])
    error_message = "Every public access block setting must be enabled on the origin bucket."
  }

  assert {
    condition     = one([for r in aws_s3_bucket_ownership_controls.site.rule : r.object_ownership]) == "BucketOwnerEnforced"
    error_message = "Object ownership must be BucketOwnerEnforced so ACLs cannot re-open the bucket."
  }

  assert {
    condition     = one([for v in aws_s3_bucket_versioning.site.versioning_configuration : v.status]) == "Enabled"
    error_message = "Versioning must stay enabled so an overwritten deploy can be recovered."
  }
}

run "cloudfront_reaches_s3_through_oac_only" {
  command = plan

  assert {
    condition     = aws_cloudfront_origin_access_control.site.signing_behavior == "always"
    error_message = "OAC must always sign requests, otherwise the bucket policy will reject them."
  }

  assert {
    condition     = aws_cloudfront_origin_access_control.site.signing_protocol == "sigv4"
    error_message = "OAC must sign with SigV4."
  }
}

run "viewer_traffic_is_tls_only" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.site.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021"
    error_message = "The distribution must reject TLS below 1.2."
  }

  assert {
    condition     = aws_cloudfront_distribution.site.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "Plain HTTP must be redirected to HTTPS."
  }

  assert {
    condition     = aws_cloudfront_distribution.site.ordered_cache_behavior[0].viewer_protocol_policy == "https-only"
    error_message = "The API behavior must refuse plain HTTP outright rather than redirecting."
  }
}

run "api_behavior_does_not_cache" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.site.ordered_cache_behavior[0].path_pattern == "/api/*"
    error_message = "API traffic must be matched by the /api/* behavior."
  }

  assert {
    condition     = aws_cloudfront_distribution.site.ordered_cache_behavior[0].cache_policy_id == data.aws_cloudfront_cache_policy.disabled.id
    error_message = "API responses must use the CachingDisabled policy; caching them would serve stale data."
  }

  assert {
    condition     = aws_cloudfront_distribution.site.ordered_cache_behavior[0].origin_request_policy_id == data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    error_message = "The API origin must not receive the CloudFront Host header, or API Gateway rejects the request."
  }
}

run "security_headers_are_applied" {
  command = plan

  assert {
    condition     = aws_cloudfront_response_headers_policy.site.security_headers_config[0].strict_transport_security[0].access_control_max_age_sec >= 31536000
    error_message = "HSTS max-age must be at least one year."
  }

  assert {
    condition     = aws_cloudfront_response_headers_policy.site.security_headers_config[0].frame_options[0].frame_option == "DENY"
    error_message = "The site must not be framable."
  }
}

run "spa_fallback_is_off_so_api_404s_survive" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.site.custom_error_response) == 0
    error_message = "Custom error responses are distribution-wide. With the API on /api/*, enabling them turns an API 404 into a 200 with an HTML body."
  }
}

run "site_content_is_uploaded_with_correct_content_type" {
  command = plan

  assert {
    condition     = aws_s3_object.site["index.html"].content_type == "text/html"
    error_message = "HTML objects must be served as text/html, not as a download."
  }

  assert {
    condition     = aws_s3_object.site["index.html"].cache_control == "public, max-age=0, must-revalidate"
    error_message = "HTML must revalidate on every request so a deploy is visible immediately."
  }
}

run "encryption_at_rest_is_configured" {
  # `rule` is a set, which cannot be indexed at plan time, so this run applies
  # against the mocked provider to materialise it.
  command = apply

  assert {
    condition = length([
      for rule in aws_s3_bucket_server_side_encryption_configuration.site.rule :
      rule if rule.apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    ]) == 1
    error_message = "The origin bucket must have default server-side encryption enabled."
  }
}

run "rejects_an_unknown_price_class" {
  command = plan

  variables {
    price_class = "PriceClass_999"
  }

  expect_failures = [var.price_class]
}

run "rejects_a_short_hsts_max_age" {
  command = plan

  variables {
    hsts_max_age_seconds = 3600
  }

  expect_failures = [var.hsts_max_age_seconds]
}

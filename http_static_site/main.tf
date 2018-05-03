variable "main_dns_name" {
  type = "string"
}

variable "alt_dns_names" {
  type    = "list"
  default = []
}

variable "route53_zone_id" {
  type = "string"
}

variable "root_object" {
  default = "index.html"
}

variable "error_object" {
  default = "404.html"
}

output "main_bucket" {
  value = {
    website_endpoint = "${aws_s3_bucket.main_bucket.website_endpoint}"
    arn              = "${aws_s3_bucket.main_bucket.arn}"
  }
}

output "redirect_buckets" {
  value = {
    website_endpoints = "${zipmap(aws_s3_bucket.redirect_buckets.*.bucket, aws_s3_bucket.redirect_buckets.*.website_endpoint)}"
    arn               = "${zipmap(aws_s3_bucket.redirect_buckets.*.bucket, aws_s3_bucket.redirect_buckets.*.arn)}"
  }
}

#--- S3 ----------------------------------------------------------------------
data "template_file" "s3_policy_annonymous_get_object" {
  template = "${file("${path.module}/templates/s3_policy_annonymous_get_object.json")}"

  vars {
    bucket_name = "${var.main_dns_name}"
  }
}

resource "aws_s3_bucket" "main_bucket" {
  bucket = "${var.main_dns_name}"
  policy = "${data.template_file.s3_policy_annonymous_get_object.rendered}"

  website {
    index_document = "${var.root_object}"
    error_document = "${var.error_object}"
  }
}

resource "aws_s3_bucket" "redirect_buckets" {
  count = "${length(var.alt_dns_names)}"

  bucket = "${var.alt_dns_names[count.index]}"

  website {
    redirect_all_requests_to = "http://${var.main_dns_name}"
  }
}

#--- Route53 -----------------------------------------------------------------
resource "aws_route53_record" "main_dns_entry" {
  name    = "${var.main_dns_name}"
  type    = "A"
  zone_id = "${var.route53_zone_id}"

  alias {
    name                   = "${aws_s3_bucket.main_bucket.website_domain}"
    zone_id                = "${aws_s3_bucket.main_bucket.hosted_zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "redirect_dns_entries" {
  count = "${length(var.alt_dns_names)}"

  name    = "${var.alt_dns_names[count.index]}"
  type    = "A"
  zone_id = "${var.route53_zone_id}"

  alias {
    name                   = "${element(aws_s3_bucket.redirect_buckets.*.website_domain, count.index)}"
    zone_id                = "${element(aws_s3_bucket.redirect_buckets.*.hosted_zone_id, count.index)}"
    evaluate_target_health = false
  }
}

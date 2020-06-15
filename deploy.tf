provider "aws" {
  profile = "Moonwalker"
  region = "ap-south-1"	
}

resource "aws_security_group" "sec_grp" {
  name        = "sec_grp"
  description = "Allow Sec inbound traffic"
  vpc_id      = "vpc-2cbda044"

  ingress {
    description = "Security from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
}
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  tags = {
    Name = "Sec_grp"
  }
}
resource "tls_private_key" "key" {
  algorithm = "RSA"
}
module "key_pair" {
  source = "terraform-aws-modules/key-pair/aws"
key_name   = "test"
  public_key = tls_private_key.key.public_key_openssh
}
resource "aws_instance" "webserver" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "mykey1"
  vpc_security_group_ids = [aws_security_group.sec_grp.id]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/lenovo/Downloads/mykey1.pem")
    host     = aws_instance.webserver.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "Static Web Server"
  }
}

resource "aws_ebs_volume" "ebs" {
  availability_zone = aws_instance.webserver.availability_zone
  size              = 1
  tags = {
    Name = "mywebserver_ebs"
  }
}


resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = "aws_ebs_volume.ebs.id"
  instance_id = "aws_instance.webserver.id"
  force_detach = true
}

resource "null_resource" "nulllocal2"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.webserver.public_ip} > publicip.txt"
  	}
}



resource "null_resource" "nullremote3"  {

depends_on = [
    aws_volume_attachment.ebs_att,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/lenovo/Downloads/mykey1.pem")
    host     = aws_instance.webserver.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Moonwalkerr/multicloud_terraform_test1 /var/www/html/"
    ]
  }
}
resource "aws_s3_bucket" "bucket" {
depends_on =[
aws_instance.webserver,
]
    bucket                = "web-bucket"
    acl                   = "private"
    region                = "ap-south-1"
   provisioner "local-exec" {
        command     = "mkdir website"
 
    }
 
  provisioner "local-exec" {
        command     = "git clone clone https://github.com/Moonwalkerr/multicloud_terraform_test1 website"
 
    }
 
 provisioner "local-exec"{
 
 when = destroy
 command  =   "echo Y | rmdir /s hello"
 }
 
  tags = {
    Name = "web-bucket"
  }
}

resource "aws_s3_bucket_object" "image" {
  depends_on =[
aws_s3_bucket.bucket,
]
  bucket = aws_s3_bucket.bucket.id
  key    = "ironman.jpg"
  source = "website/iron_man.jpg"
  content_type ="image/jpg"
  acl="public-read"
}

resource "aws_s3_bucket_public_access_block" "public_storage" {
    depends_on = [
        aws_s3_bucket.bucket,
    ]
    bucket                = "web-bucket"
    block_public_acls     = false 
    block_public_policy   = false
}
locals {
  s3_origin_id = "aws_s3_bucket.bucket.id"
}
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
depends_on =[
aws_s3_bucket_object.image,
]
}
resource "aws_cloudfront_distribution" "cloudfront" {
depends_on =[
aws_cloudfront_origin_access_identity.origin_access_identity,
]
  origin {
    domain_name = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
s3_origin_config {
  origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
}
  }
enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "1.png"
default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
forwarded_values {
      query_string = false
cookies {
        forward = "none"
      }
    }
viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
price_class = "PriceClass_200"
restrictions {
    geo_restriction {
      restriction_type = "none"
      
    }
  }
tags = {
    Environment = "production"
  }
viewer_certificate {
    cloudfront_default_certificate = true
  }
  connection {
    type     = "ssh"
    user     = "ec2-user"
     private_key = file("C:/Users/lenovo/Downloads/mykey1.pem")
  port=22
    host = aws_instance.webserver.public_ip
  }
   }
data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.bucket.arn}/*"]
principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.bucket.arn}"]
principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
}
resource "aws_s3_bucket_policy" "bucket" {
  bucket = "aws_s3_bucket.bucket.id"
  policy = "${data.aws_iam_policy_document.s3_policy.json}"
}
output "cloudfront_ip" {
  value = aws_cloudfront_distribution.cloudfront.domain_name
}
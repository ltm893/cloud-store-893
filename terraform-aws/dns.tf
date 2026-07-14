resource "aws_route53_record" "app" {
  count = var.create_dns_record ? 1 : 0

  zone_id = data.aws_route53_zone.parent[0].zone_id
  name    = var.app_hostname
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

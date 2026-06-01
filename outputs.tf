output "nginx_private_ip" {
  description = "Private IP of NGINX EC2"
  value       = aws_instance.nginx.private_ip
}

output "wireguard_public_ip" {
  description = "Public IP of WireGuard server"
  value       = aws_instance.wireguard.public_ip
}
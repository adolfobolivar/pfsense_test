output "pfsense_public_ip" {
  description = "Elastic IP address of the pfSense WAN interface"
  value       = aws_eip.pfsense_eip.public_ip
}

output "pfsense_wan_private_ip" {
  description = "Private IP of the pfSense WAN ENI (WAN subnet)"
  value       = aws_network_interface.pfsense_wan_eni.private_ip
}

output "pfsense_lan_ip" {
  description = "Private IP of the pfSense LAN ENI – default gateway for LAN hosts"
  value       = aws_network_interface.pfsense_lan_eni.private_ip
}

output "ubuntu_private_ip" {
  description = "Private IP of the Ubuntu server (LAN subnet)"
  value       = aws_instance.ubuntu.private_ip
}

output "key_pair_name" {
  description = "EC2 Key Pair name created in AWS"
  value       = aws_key_pair.pfsense_key.key_name
}

output "private_key_path" {
  description = "Local path to the generated private key PEM file"
  value       = local_sensitive_file.pfsense_pem.filename
}

output "ssh_pfsense" {
  description = "SSH command to connect to pfSense (via WAN EIP)"
  value       = "ssh -i ${local_sensitive_file.pfsense_pem.filename} admin@${aws_eip.pfsense_eip.public_ip}"
}

output "ssh_ubuntu_via_pfsense" {
  description = "SSH command to reach the Ubuntu server through pfSense as a jump host"
  value       = "ssh -i ${local_sensitive_file.pfsense_pem.filename} -J admin@${aws_eip.pfsense_eip.public_ip} ubuntu@${aws_instance.ubuntu.private_ip}"
}

output "ipsec_encryption_domain_ip" {
  description = "Reserved EIP for IPsec encryption domain (Twilio Interconnect policy-based VPN)"
  value       = aws_eip.ipsec_encryption_domain_eip.public_ip
}

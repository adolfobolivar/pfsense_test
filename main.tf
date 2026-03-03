
terraform {
  required_version = "~> 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.26"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region     = local.config.aws_region
  access_key = local.secrets.aws_access_key
  secret_key = local.secrets.aws_secret_key
}

# 0. EC2 Key Pair
resource "tls_private_key" "pfsense_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "pfsense_key" {
  key_name   = local.config.key_name
  public_key = tls_private_key.pfsense_key.public_key_openssh
  tags       = { Name = "pfsense-key" }
}

resource "local_sensitive_file" "pfsense_pem" {
  content         = tls_private_key.pfsense_key.private_key_pem
  filename        = "${path.module}/${local.config.key_name}.pem"
  file_permission = "0400"
}

# 1. VPC
resource "aws_vpc" "pfsense_vpc" {
  cidr_block           = local.config.vpc_cidr
  enable_dns_hostnames = true
  tags = {
    Name = "pfsense-vpc"
  }
}

# 2. Subnets
resource "aws_subnet" "wan_subnet" {
  vpc_id                  = aws_vpc.pfsense_vpc.id
  cidr_block              = local.config.wan_subnet_cidr
  map_public_ip_on_launch = false
  availability_zone       = local.config.availability_zone
  tags = {
    Name    = "WAN Subnet"
    Network = "WAN"
  }
}

resource "aws_subnet" "lan_subnet" {
  vpc_id                  = aws_vpc.pfsense_vpc.id
  cidr_block              = local.config.lan_subnet_cidr
  map_public_ip_on_launch = false
  availability_zone       = local.config.availability_zone
  tags = {
    Name    = "LAN Subnet"
    Network = "LAN"
  }
}

# 3. Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.pfsense_vpc.id
  tags = {
    Name    = "pfsense-igw"
    Network = "WAN"
  }
}

# 4. WAN Route Table – default route to IGW
resource "aws_route_table" "wan_rt" {
  vpc_id = aws_vpc.pfsense_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name    = "WAN Route Table"
    Network = "WAN"
  }
}

resource "aws_route_table_association" "wan_rta" {
  subnet_id      = aws_subnet.wan_subnet.id
  route_table_id = aws_route_table.wan_rt.id
}

# 5. LAN Route Table – default route to pfSense LAN ENI
resource "aws_route_table" "lan_rt" {
  vpc_id = aws_vpc.pfsense_vpc.id
  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_network_interface.pfsense_lan_eni.id
  }
  tags = {
    Name    = "LAN Route Table"
    Network = "LAN"
  }
}

resource "aws_route_table_association" "lan_rta" {
  subnet_id      = aws_subnet.lan_subnet.id
  route_table_id = aws_route_table.lan_rt.id
}

# 6. Security Groups

# pfSense WAN – internet-facing (IPsec + management from admin IP)
resource "aws_security_group" "pfsense_wan_sg" {
  name        = "pfsense-wan-sg"
  description = "pfSense WAN: IPsec and management access"
  vpc_id      = aws_vpc.pfsense_vpc.id

  ingress {
    description = "IPsec IKE"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "IPsec NAT-T"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  dynamic "ingress" {
    for_each = local.config.admin_ip_ranges
    content {
      description = "SSH management"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }
  dynamic "ingress" {
    for_each = local.config.admin_ip_ranges
    content {
      description = "HTTPS management"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name    = "pfsense-wan-sg"
    Network = "WAN"
  }
}

# pfSense LAN – accepts all traffic from the LAN subnet
resource "aws_security_group" "pfsense_lan_sg" {
  name        = "pfsense-lan-sg"
  description = "pfSense LAN: allow all traffic from LAN subnet"
  vpc_id      = aws_vpc.pfsense_vpc.id

  ingress {
    description = "All traffic from LAN subnet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.config.lan_subnet_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name    = "pfsense-lan-sg"
    Network = "LAN"
  }
}

# Ubuntu server – SSH reachable only from within the LAN subnet
resource "aws_security_group" "ubuntu_sg" {
  name        = "ubuntu-sg"
  description = "Ubuntu server: SSH from LAN subnet only"
  vpc_id      = aws_vpc.pfsense_vpc.id

  ingress {
    description = "SSH from LAN"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.config.lan_subnet_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name    = "ubuntu-sg"
    Network = "LAN"
  }
}

# 7. pfSense Network Interfaces

resource "aws_network_interface" "pfsense_wan_eni" {
  subnet_id         = aws_subnet.wan_subnet.id
  source_dest_check = false
  security_groups   = [aws_security_group.pfsense_wan_sg.id]
  tags = {
    Name    = "pfsense-wan-eni"
    Network = "WAN"
  }
}

resource "aws_network_interface" "pfsense_lan_eni" {
  subnet_id         = aws_subnet.lan_subnet.id
  private_ips       = [local.config.pfsense_lan_ip]
  source_dest_check = false
  security_groups   = [aws_security_group.pfsense_lan_sg.id]
  tags = {
    Name    = "pfsense-lan-eni"
    Network = "LAN"
  }
}

# 8. pfSense Instance (dual-NIC: WAN = eth0, LAN = eth1)
resource "aws_instance" "pfsense" {
  ami           = local.config.ami_id
  instance_type = local.config.instance_type
  key_name      = aws_key_pair.pfsense_key.key_name

  # Attach pre-created ENIs; source_dest_check is set on the ENIs themselves.
  # network_interface blocks are deprecated but remain the only way to attach
  # pre-created ENIs at launch time (primary_network_interface_id is read-only).
  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.pfsense_wan_eni.id
  }
  network_interface {
    device_index         = 1
    network_interface_id = aws_network_interface.pfsense_lan_eni.id
  }

  tags = {
    Name    = "pfsense-firewall"
    Network = "WAN+LAN"
  }
}

# 9. Elastic IP – attached to pfSense WAN ENI
# depends_on aws_instance.pfsense prevents a race condition where Terraform
# would try to associate the EIP while the instance is still attaching the ENI.
resource "aws_eip" "pfsense_eip" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.pfsense_wan_eni.id
  associate_with_private_ip = aws_network_interface.pfsense_wan_eni.private_ip
  depends_on                = [aws_internet_gateway.igw, aws_instance.pfsense]
  tags = {
    Name    = "pfsense-wan-eip"
    Network = "WAN"
  }
}

# 10. Ubuntu Server (private, LAN subnet)
# depends_on ensures:
#   - pfSense is fully created and its LAN ENI is attached before Ubuntu boots
#   - LAN route table is associated with the LAN subnet so the default gateway
#     via pfSense LAN ENI is in place before the instance first sends traffic
resource "aws_instance" "ubuntu" {
  ami           = local.config.ubuntu_ami_id
  instance_type = local.config.instance_type
  key_name      = aws_key_pair.pfsense_key.key_name

  subnet_id              = aws_subnet.lan_subnet.id
  private_ip             = local.config.ubuntu_private_ip
  vpc_security_group_ids = [aws_security_group.ubuntu_sg.id]

  depends_on = [
    aws_instance.pfsense,
    aws_route_table_association.lan_rta,
  ]

  tags = {
    Name    = "ubuntu-server"
    Network = "LAN"
  }
}

#!/bin/bash
# Phase 1: Network (VPC, subnets, routing)

export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1

# VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lab-vpc}]' \
  --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames

# Public subnet
PUB=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-public-1a}]' \
  --query Subnet.SubnetId --output text)
aws ec2 modify-subnet-attribute --subnet-id $PUB --map-public-ip-on-launch

# Private subnets
PRIV_A=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-private-1a}]' \
  --query Subnet.SubnetId --output text)
PRIV_B=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.3.0/24 --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-private-1b}]' \
  --query Subnet.SubnetId --output text)

# Internet gateway and public route table
IGW=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_ID
PUB_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id $PUB_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB

# Save the IDs for later phases (.env is gitignored)
cat > .env << EOF
VPC_ID=$VPC_ID
PUB=$PUB
PRIV_A=$PRIV_A
PRIV_B=$PRIV_B
IGW=$IGW
PUB_RT=$PUB_RT
EOF

echo "VPC: $VPC_ID | Public: $PUB | Private: $PRIV_A, $PRIV_B | IGW: $IGW"

# Phase 2: Security groups and web server

MYIP=$(curl -s https://checkip.amazonaws.com)

WEB_SG=$(aws ec2 create-security-group --group-name lab-web-sg --description "Web server" \
  --vpc-id $VPC_ID --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $WEB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $WEB_SG --protocol tcp --port 22 --cidr $MYIP/32

DB_SG=$(aws ec2 create-security-group --group-name lab-db-sg --description "Database" \
  --vpc-id $VPC_ID --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $DB_SG --protocol tcp --port 3306 --source-group $WEB_SG

# Key pair is stored outside the repo
mkdir -p ~/.ssh
aws ec2 create-key-pair --key-name lab-key --query KeyMaterial --output text > ~/.ssh/lab-key.pem
chmod 400 ~/.ssh/lab-key.pem

# Launch the web server (scripts/user-data.sh installs Apache)
AMI=$(MSYS_NO_PATHCONV=1 aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)

INSTANCE_ID=$(aws ec2 run-instances --image-id $AMI --instance-type t3.micro --key-name lab-key \
  --subnet-id $PUB --security-group-ids $WEB_SG --user-data file://scripts/user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=lab-web}]' \
  --query 'Instances[0].InstanceId' --output text)

aws ec2 wait instance-running --instance-ids $INSTANCE_ID
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

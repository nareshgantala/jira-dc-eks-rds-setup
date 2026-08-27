## VPC

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "${var.project}-${var.env}-vpc"
  }
}

## SUBNETS

resource "aws_subnet" "public_subnet" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                                                          = "${var.project}-${var.env}-public-subnet-${count.index + 1}",
    "kubernetes.io/role/elb"                                      = "1",
    "kubernetes.io/cluster/${var.project}-${var.env}-eks-cluster" = "shared"
  }
}


resource "aws_subnet" "private_subnet" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 3)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                                                          = "${var.project}-${var.env}-private-subnet-${count.index + 1}",
    "kubernetes.io/role/internal-elb"                             = "1",
    "kubernetes.io/cluster/${var.project}-${var.env}-eks-cluster" = "shared"
  }
}


## IGW
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.env}-igw"
  }
}

## NAT GW

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet[0].id

  tags = {
    Name = "${var.project}-${var.env}-nat-gw"
  }

  depends_on = [aws_internet_gateway.main]
}


##ROUTE TABLES

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project}-${var.env}-public-route-table"
  }
}

resource "aws_route_table_association" "public-subnet-association" {
  count          = 3
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project}-${var.env}-private-route-table"
  }
}

resource "aws_route_table_association" "private-subnet-association" {
  count          = 3
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}


resource "aws_db_subnet_group" "jira_dc_db_subnet_group" {
  name       = "jira-dc-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet[0].id, aws_subnet.private_subnet[1].id, aws_subnet.private_subnet[2].id]

  tags = {
    Name = "jira-dc-db-subnet-group"
  }
}

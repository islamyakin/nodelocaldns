variable "eks_svc_cidr" {
  type = string
}

eks_svc_cidr                    = "172.29.0.0/19"

locals {
    eks_dns_ip = cidrhost(var.eks_svc_cidr, 10)
}

data "aws_ami" "eks_default" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-1.27-v*"]
  }
}


module "eks" {
  depends_on = [ 
    aviatrix_spoke_transit_attachment.aws_uswest2["10.20.0.0/16"],
    aviatrix_fqdn.main
   ]
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.2"

  cluster_name                   = "eks-${var.k8s_cluster_name}"
  cluster_version                = "1.27"
  cluster_endpoint_public_access = true
  cluster_endpoint_private_access = false
  cluster_ip_family              = "ipv4"
  cluster_service_ipv4_cidr      = var.eks_svc_cidr

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  
  vpc_id                   = aws_vpc.aws_vpc[var.aws_spoke_vnets[var.eks_region]["vnet_cidr_list"][0]].id
  subnet_ids               = [aws_subnet.eks_node_subnet_1[var.aws_spoke_vnets[var.eks_region]["vnet_cidr_list"][0]].id, aws_subnet.eks_node_subnet_2[var.aws_spoke_vnets[var.eks_region]["vnet_cidr_list"][0]].id]
  control_plane_subnet_ids = [aws_subnet.eks_master_subnet_1[var.aws_spoke_vnets[var.eks_region]["vnet_cidr_list"][0]].id, aws_subnet.eks_master_subnet_2[var.aws_spoke_vnets[var.eks_region]["vnet_cidr_list"][0]].id]
  cluster_security_group_name = "eks-sg"
  create_cluster_security_group = true
  create_cluster_primary_security_group_tags = true
  create_node_security_group = true
  cluster_security_group_additional_rules = {
  rfc1918_a = {
    description = "Allow all RFC1918-A traffic"
    type        = "ingress"
    protocol    = "all"
    from_port   = 0
    to_port     = 65535
    cidr_blocks = ["10.0.0.0/8"]
  },
  rfc1918_b = {
    description = "Allow all RFC1918-B traffic"
    type        = "ingress"
    protocol    = "all"
    from_port   = 0
    to_port     = 65535
    cidr_blocks = ["172.16.0.0/12"]
  },
  rfc1918_c = {
    description = "Allow all RFC1918-C traffic"
    type        = "ingress"
    protocol    = "all"
    from_port   = 0
    to_port     = 65535
    cidr_blocks = ["192.168.0.0/16"]
  },
  deployer = {
    description = "deployer"
    type        = "ingress"
    protocol    = "all"
    from_port   = 0
    to_port     = 65535
    cidr_blocks = [replace(data.http.my_ip.body, "\n", "/32")]
  }
}


  # Self managed node groups will not automatically create the aws-auth configmap so we need to
  create_aws_auth_configmap = true
  create                    = true
  manage_aws_auth_configmap = true

  self_managed_node_group_defaults = {
    # enable discovery of autoscaling groups by cluster-autoscaler
    autoscaling_group_tags = {
      "k8s.io/cluster-autoscaler/enabled" : true
      "k8s.io/cluster-autoscaler/eks-${var.k8s_cluster_name}" : "owned"
    }
  }

  self_managed_node_groups = {
    # Default node group - as provisioned by the module defaults
    default_node_group = {
      instance_type = var.eks_vm_sku
    }

  complete = {
      name            = "complete-self-mng"
      use_name_prefix = false
      cluster_ip_family = "ipv4"
      key_name = aws_key_pair.aws_key_pair[var.eks_region].key_name

      subnet_ids = [aws_subnet.eks_node_subnet_1[var.aws_spoke_vnets[var.eks_region]["vnet_cidr_list"][0]].id, aws_subnet.eks_node_subnet_2[var.aws_spoke_vnets[var.eks_region]["vnet_cidr_list"][0]].id]
      vpc_security_group_ids = [aws_security_group.private_subnet_sg[var.aws_spoke_vnets[var.eks_region]["vnet_cidr_list"][0]].id]

      min_size     = 1
      max_size     = 7
      desired_size = 2

      ami_id = data.aws_ami.eks_default.id

      instance_type = var.eks_vm_sku
      bootstrap_extra_args = "--kubelet-extra-args '--dns-cluster-ip=${local.eks_dns_ip}'"

      launch_template_name            = "eks-tempalte-group"
      launch_template_use_name_prefix = true
      launch_template_description     = "Self managed node group example launch template"

      ebs_optimized     = false
      enable_monitoring = false
      create_iam_role          = true
      iam_role_name            = "eks-node-group-role"
      iam_role_attach_cni_policy = true
      create_iam_instance_profile = true
      iam_role_use_name_prefix = false
      iam_role_description     = "Self managed node group role"
      iam_role_tags = {
        Purpose = "Protector of the kubelet"
      }

      timeouts = {
        create = "80m"
        update = "80m"
        delete = "80m"
      }

      tags = {
        environment = "prod"
      }
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}
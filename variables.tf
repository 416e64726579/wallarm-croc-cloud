variable "region" {
  type    = string
  default = "croc"
}

variable "instance_type" {
  type    = string
  default = "c3.4large"
}

variable "ami" {
  type    = string
  default = "cmi-74DB8E26"
}

variable "subnet_id" {
  type    = string
  default = "subnet-BF7BF195"
}

variable "security_groups" {
  default = ["sg-A4DB1AFC"]
}

variable "az" {
  type    = string
  default = "ru-msk-vol51"
}

variable "tarantool_memory" {
  type    = number
  default = 4
}

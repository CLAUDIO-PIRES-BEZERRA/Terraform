terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }

  required_version = ">= 0.13"
}

provider "azurerm" {
  skip_provider_registration = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

resource "azurerm_resource_group" "rg-aula-vm" {
  name     = "rg-aula-vm"
  location = "eastus"

  tags = {
    "aula" = "vm"
  }
}

resource "azurerm_virtual_network" "vnet-aula" {
  name                = "vnet-aula"
  location            = azurerm_resource_group.rg-aula-vm.location
  resource_group_name = azurerm_resource_group.rg-aula-vm.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    environment = "Production"
  }
}

resource "azurerm_subnet" "sub-aula" {
  name                 = "sub-aula"
  resource_group_name  = azurerm_resource_group.rg-aula-vm.name
  virtual_network_name = azurerm_virtual_network.vnet-aula.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "pip-aula" {
  name                = "pip-aula"
  resource_group_name = azurerm_resource_group.rg-aula-vm.name
  location            = azurerm_resource_group.rg-aula-vm.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
  }
}

resource "azurerm_network_security_group" "nsg-aula" {
  name                = "nsg-aula"
  location            = azurerm_resource_group.rg-aula-vm.location
  resource_group_name = azurerm_resource_group.rg-aula-vm.name

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "web"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "Production"
  }
}

resource "azurerm_network_interface" "nic-aula" {
  name                = "nic-aula"
  location            = azurerm_resource_group.rg-aula-vm.location
  resource_group_name = azurerm_resource_group.rg-aula-vm.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sub-aula.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip-aula.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic-nsg-aula" {
  network_interface_id      = azurerm_network_interface.nic-aula.id
  network_security_group_id = azurerm_network_security_group.nsg-aula.id
}

resource "azurerm_linux_virtual_machine" "vm-aula" {
  name                            = "vm-aula"
  resource_group_name             = azurerm_resource_group.rg-aula-vm.name
  location                        = azurerm_resource_group.rg-aula-vm.location
  size                            = "Standard_DS1_v2"
  admin_username                  = "adminuser"
  admin_password                  = "d210szD$"
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.nic-aula.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }
}

resource "null_resource" "install-nginx" {
  triggers = {
    order = azurerm_linux_virtual_machine.vm-aula.id
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = "adminuser"
      password = "d210szD$"
      host     = azurerm_public_ip.pip-aula.ip_address
    }
    inline = [
      "sudo apt update",
      "sudo apt install -y nginx"
    ]
  }

  depends_on = [azurerm_linux_virtual_machine.vm-aula]
}

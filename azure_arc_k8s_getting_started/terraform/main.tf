# Create an Azure Resource Group
resource "azurerm_resource_group" "arck3sdemo" {
    name = "${var.azure_resource_group}-RG"
    location = "${var.location}"
}

# Create an Azure Virtual Network
resource "azurerm_virtual_network" "arck3sdemo" {
    name = "${var.azure_vnet}-VNET"
    address_space = ["${var.azure_vnet_address_space}"]
    resource_group_name = "${azurerm_resource_group.arck3sdemo.name}"
    location = "${var.location}"
}

# Create an Azure Virtual Network Subnet
resource "azurerm_subnet" "arck3sdemo" {
    name = "${var.azure_vnet_subnet}"
    resource_group_name  = "${azurerm_resource_group.arck3sdemo.name}"
    virtual_network_name = "${azurerm_virtual_network.arck3sdemo.name}"
    address_prefix = "${var.azure_subnet_address_prefix}"
}

# Create an Azure Public IP resource
resource "azurerm_public_ip" "arck3sdemo" {
    name = "${var.azure_public_ip}-PIP-${format("%02d", count.index+1)}"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.arck3sdemo.name}"
    allocation_method = "Static"
    count = "${var.count}"
}

# Create an Azure Network Secuirty Group (NSG) resource with inbound rules
resource "azurerm_network_security_group" "arck3sdemo" {
    name = "${var.azure_nsg}-NSG"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.arck3sdemo.name}"

    security_rule {
    name = "allow_SSH"
    description = "Allow Remote Desktop access"
    priority = 1001
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "22"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
      security_rule {
    name = "allow_Cluster_API"
    description = "Allow Remote Desktop access"
    priority = 1002
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "22"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
}

# Create an Azure Network Interface resource and attaching previously created NSG and public IP resources
resource "azurerm_network_interface" "arck3sdemo" {
    count = "${var.count}"
    name = "${var.azure_vm_nic}-NIC-${format("%02d", count.index+1)}"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.arck3sdemo.name}"
    network_security_group_id = "${azurerm_network_security_group.arck3sdemo.id}"
    
    ip_configuration {
        name = "arck3sdemo"
        subnet_id = "${azurerm_subnet.arck3sdemo.id}"
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id = "${element(azurerm_public_ip.arck3sdemo.*.id, count.index)}" 
    }
}

# Create an Azure VM Availability Set
resource "azurerm_availability_set" "arck3sdemo" {
  count = "${var.count}"
  name = "${var.azure_vm_aset_name}-ASET-${format("%02d", count.index+1)}"
  location = "${var.location}"
  resource_group_name = "${azurerm_resource_group.arck3sdemo.name}"
  platform_fault_domain_count = 3
  platform_update_domain_count = 5
  managed = true
}

# Create an Azure VM
resource "azurerm_virtual_machine" "arck3sdemo" {
    count = "${var.count}"
    name = "${var.azure_vm_name}-${format("%02d", count.index+1)}"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.arck3sdemo.name}"
    network_interface_ids = ["${element(azurerm_network_interface.arck3sdemo.*.id, count.index)}"]
    vm_size = "${var.azure_vm_size}"
    availability_set_id = "${element(azurerm_availability_set.arck3sdemo.*.id, count.index)}"
    delete_os_disk_on_termination = true
    delete_data_disks_on_termination = true

    storage_image_reference {
        publisher = "Canonical"
        offer = "UbuntuServer"
        sku = "18.04-LTS"
        version = "latest"
    }

    storage_os_disk {
        name= "${var.azure_storage_os_disk}-OS-Disk-${format("%02d", count.index+1)}"
        caching= "ReadWrite"
        create_option= "FromImage"
        managed_disk_type = "Premium_LRS"
        disk_size_gb= "64"
    }

# Set hostname, username & password
    os_profile {
        computer_name = "${var.azure_vm_os_profile}-${format("%02d", count.index+1)}"
        admin_username = "${var.admin_username}"
        admin_password = "${var.admin_password}"
    }

    os_profile_linux_config {
        disable_password_authentication = false
    }   

# Install updates and packages
    provisioner "file" {
        source      = "scripts/install_k3s.sh"
        destination = "/tmp/install_k3s.sh"
        connection {
            type = "ssh"
            host = "${element(azurerm_public_ip.arck3sdemo.*.ip_address, count.index)}"
            user = "${var.admin_username}"
            password = "${var.admin_password}"
            timeout = "2m"
        }        
    }
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            host = "${element(azurerm_public_ip.arck3sdemo.*.ip_address, count.index)}"
            user = "${var.admin_username}"
            password = "${var.admin_password}"
            timeout = "2m"
        }    
        inline = [
            "chmod +x /tmp/script.sh",
            "/tmp/script.sh"
            ]
        }
}

# List VM public IPs
data "azurerm_public_ip" "arck3sdemo" { 
  count = "${var.count}"
  name = "${element(azurerm_public_ip.arck3sdemo.*.name, count.index)}"
  resource_group_name = "${azurerm_resource_group.arck3sdemo.name}"
}

output "public_ip_address" {
  value = "${data.azurerm_public_ip.arck3sdemo.*.ip_address}"
}

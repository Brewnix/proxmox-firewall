#!/bin/bash
set -e

# This script should be run on the Proxmox host as root

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Setting up Terraform API access for Proxmox${NC}"

# 1. Create a role for Terraform with required privileges
echo -e "${GREEN}Creating Terraform role...${NC}"
pveum role add TerraformProv -privs "Pool.Allocate VM.Console VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.Audit VM.PowerMgmt Datastore.AllocateSpace Datastore.Audit"

# 2. Create a user for Terraform
echo -e "${GREEN}Creating Terraform user...${NC}"
pveum user add tfuser@pve --password "temppassword123"

# 3. Assign the role to the user
echo -e "${GREEN}Assigning role to user...${NC}"
pveum aclmod / -user tfuser@pve -role TerraformProv

# 4. Create API token for the user (with no expiry)
echo -e "${GREEN}Creating API token...${NC}"
TOKEN_OUTPUT=$(pveum user token add tfuser@pve terraform --privsep 0)

# 5. Extract the secret from the output
API_SECRET=$(echo "$TOKEN_OUTPUT" | grep -oP "value: \K[^ ]+")

# 6. Display the result and instructions
echo -e "${YELLOW}===========================${NC}"
echo -e "${YELLOW}TERRAFORM API SETUP COMPLETE${NC}"
echo -e "${YELLOW}===========================${NC}"
echo
echo -e "${GREEN}API Token ID:${NC} tfuser@pve!terraform"
echo -e "${GREEN}API Token Secret:${NC} $API_SECRET"
echo
echo -e "${YELLOW}IMPORTANT:${NC} Add this token secret to your .env file:"
echo "PROXMOX_API_SECRET=\"$API_SECRET\""
echo
echo -e "${YELLOW}For security reasons, you might want to change the user password:${NC}"
echo "pveum user modify tfuser@pve --password \"your-secure-password\""

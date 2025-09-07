#!/bin/bash

# Setup Fork Script
# This script helps users update all GitHub URLs to their own fork
# Usage: ./scripts/setup-fork.sh <your-github-username>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}$1${NC}"
}

# Check if username is provided
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <your-github-username>"
    echo ""
    echo "Example: $0 myusername"
    echo "This will update all GitHub URLs from 'Brewnix/proxmox-firewall' to 'myusername/proxmox-firewall'"
    exit 1
fi

USERNAME="$1"
REPO_NAME="proxmox-firewall"
OLD_URL="Brewnix/proxmox-firewall"
NEW_URL="${USERNAME}/${REPO_NAME}"

print_header "=================================================="
print_header "Proxmox Firewall Fork Setup"
print_header "=================================================="
echo ""
print_status "Updating GitHub URLs from '${OLD_URL}' to '${NEW_URL}'"
echo ""

# Check if we're in the right directory
if [ ! -f "README.md" ] || [ ! -d "deployment" ]; then
    print_error "This script must be run from the root of the proxmox-firewall repository"
    exit 1
fi

# Backup original files
print_status "Creating backups of original files..."
BACKUP_DIR=".fork-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# List of files to update
FILES_TO_UPDATE=(
    "README.md"
    "CONTRIBUTING.md"
    "docs/reference/FAQ.md"
    "deployment/ansible/master_playbook.yml"
    "deployment/ansible/playbooks/site_deployment.yml"
)

# Create backups
for file in "${FILES_TO_UPDATE[@]}"; do
    if [ -f "$file" ]; then
        cp "$file" "$BACKUP_DIR/"
        print_status "Backed up: $file"
    fi
done

print_status "Backups created in: $BACKUP_DIR"
echo ""

# Function to update URLs in a file
update_file() {
    local file="$1"
    local description="$2"

    if [ ! -f "$file" ]; then
        print_warning "File not found: $file (skipping)"
        return
    fi

    print_status "Updating $description: $file"

    # Use sed to replace all instances of the old URL with the new URL
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|Brewnix/proxmox-firewall|${NEW_URL}|g" "$file"
    else
        # Linux
        sed -i "s|Brewnix/proxmox-firewall|${NEW_URL}|g" "$file"
    fi
}

# Update all files
print_status "Updating GitHub URLs in documentation and configuration files..."
echo ""

update_file "README.md" "main README"
update_file "CONTRIBUTING.md" "contributing guide"
update_file "docs/reference/FAQ.md" "FAQ documentation"
update_file "deployment/ansible/master_playbook.yml" "Ansible master playbook"
update_file "deployment/ansible/playbooks/site_deployment.yml" "Ansible site deployment playbook"

echo ""
print_status "URL updates completed!"
echo ""

# Show what was changed
print_header "Summary of Changes:"
echo ""
print_status "Updated GitHub URLs in the following files:"
for file in "${FILES_TO_UPDATE[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    fi
done

echo ""
print_status "All instances of 'Brewnix/proxmox-firewall' have been replaced with '${NEW_URL}'"
echo ""

# Verify changes
print_header "Verification:"
echo ""
REMAINING=$(grep -r "Brewnix/proxmox-firewall" README.md CONTRIBUTING.md docs/ deployment/ 2>/dev/null | wc -l || echo "0")
if [ "$REMAINING" -eq 0 ]; then
    print_status "✓ All Brewnix URLs have been successfully updated"
else
    print_warning "⚠ Found $REMAINING remaining Brewnix URLs (may be in other files)"
    print_status "Run this command to see remaining instances:"
    echo "  grep -r 'Brewnix/proxmox-firewall' ."
fi

echo ""
print_header "Next Steps:"
echo ""
print_status "1. Review the changes:"
echo "   git diff"
echo ""
print_status "2. Commit the changes:"
echo "   git add ."
echo "   git commit -m 'Update GitHub URLs for fork'"
echo ""
print_status "3. Push to your fork:"
echo "   git remote set-url origin https://github.com/${NEW_URL}.git"
echo "   git push origin main"
echo ""
print_status "4. If you need to revert changes:"
echo "   cp $BACKUP_DIR/* ."
echo ""

print_header "=================================================="
print_header "Fork setup complete!"
print_header "=================================================="

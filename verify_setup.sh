#!/bin/bash

# システム構築完了検証スクリプト

echo "=========================================="
echo "Document OCR System - Setup Verification"
echo "=========================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✓${NC} $1"
        return 0
    else
        echo -e "${RED}✗${NC} $1 (missing)"
        return 1
    fi
}

check_dir() {
    if [ -d "$1" ]; then
        echo -e "${GREEN}✓${NC} $1"
        return 0
    else
        echo -e "${RED}✗${NC} $1 (missing)"
        return 1
    fi
}

echo "1. Core Files Check"
echo "-------------------"
check_file "docker-compose.yml"
check_file ".env.docker"
check_file "README.md"
check_file "QUICKSTART.md"
check_file "DEPLOYMENT_COMMANDS.md"
check_file "SYSTEM_SUMMARY.md"
check_file "kintone_316_fields.json"
check_file ".gitignore"
echo ""

echo "2. Rails App Check"
echo "------------------"
check_dir "rails_app"
check_file "rails_app/Dockerfile.mysql"
check_file "rails_app/Gemfile"
check_file "rails_app/app/services/django_pdf_parser.rb"
check_file "rails_app/app/services/kintone_service.rb"
check_file "rails_app/app/controllers/estimates_controller.rb"
check_file "rails_app/app/controllers/kintone_controller.rb"
check_file "rails_app/app/controllers/application_controller.rb"
check_file "rails_app/config/routes.rb"
echo ""

echo "3. Django App Check"
echo "-------------------"
check_dir "django_ocr"
check_file "django_ocr/Dockerfile"
check_file "django_ocr/requirements.txt"
check_file "django_ocr/manage.py"
check_file "django_ocr/config/settings.py"
check_file "django_ocr/config/urls.py"
check_file "django_ocr/config/wsgi.py"
check_file "django_ocr/parser/models.py"
check_file "django_ocr/parser/views.py"
check_file "django_ocr/parser/urls.py"
check_file "django_ocr/utils/normalizer.py"
check_file "django_ocr/utils/vision_ocr.py"
echo ""

echo "4. Docker Configuration Check"
echo "------------------------------"
check_dir "docker/mysql/init"
check_file "docker/mysql/init/01-create-databases.sql"
echo ""

echo "5. Google Cloud Credentials Check"
echo "----------------------------------"
if [ -f "google-key.json" ]; then
    echo -e "${GREEN}✓${NC} google-key.json (found)"
    echo "  → Vision API will be used"
else
    echo -e "${YELLOW}⚠${NC} google-key.json (not found)"
    echo "  → System will use dummy data (this is OK for testing)"
fi
echo ""

echo "6. Environment Variables Check"
echo "-------------------------------"
if [ -f ".env.docker" ]; then
    echo -e "${GREEN}✓${NC} .env.docker exists"

    # Check for required variables
    if grep -q "KINTONE_DOMAIN=" .env.docker; then
        kintone_domain=$(grep "KINTONE_DOMAIN=" .env.docker | cut -d'=' -f2)
        if [ "$kintone_domain" = "your-domain.cybozu.com" ]; then
            echo -e "${YELLOW}⚠${NC} KINTONE_DOMAIN not configured (using default)"
        else
            echo -e "${GREEN}✓${NC} KINTONE_DOMAIN configured: $kintone_domain"
        fi
    fi

    if grep -q "KINTONE_API_TOKEN=" .env.docker; then
        kintone_token=$(grep "KINTONE_API_TOKEN=" .env.docker | cut -d'=' -f2)
        if [ "$kintone_token" = "your-api-token-here" ]; then
            echo -e "${YELLOW}⚠${NC} KINTONE_API_TOKEN not configured (using default)"
        else
            echo -e "${GREEN}✓${NC} KINTONE_API_TOKEN configured"
        fi
    fi
else
    echo -e "${RED}✗${NC} .env.docker not found"
fi
echo ""

echo "7. Docker Check"
echo "---------------"
if command -v docker &> /dev/null; then
    echo -e "${GREEN}✓${NC} Docker installed: $(docker --version)"
else
    echo -e "${RED}✗${NC} Docker not installed"
fi

if command -v docker-compose &> /dev/null; then
    echo -e "${GREEN}✓${NC} Docker Compose installed: $(docker-compose --version)"
else
    echo -e "${RED}✗${NC} Docker Compose not installed"
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "Ready to start the system!"
echo ""
echo "Next steps:"
echo "  1. (Optional) Place google-key.json in project root"
echo "  2. (Optional) Configure kintone settings in .env.docker"
echo "  3. Run: docker-compose up --build"
echo "  4. Wait 2-3 minutes for services to start"
echo "  5. Check: curl http://localhost:3000/health"
echo ""
echo "For detailed instructions, see:"
echo "  - QUICKSTART.md (quick start guide)"
echo "  - README.md (complete documentation)"
echo "  - DEPLOYMENT_COMMANDS.md (command reference)"
echo ""

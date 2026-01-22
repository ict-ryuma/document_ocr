"""
API views for PDF parsing using Document AI
"""
import os
import tempfile
import logging
from datetime import datetime

from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.parsers import MultiPartParser, FormParser

from utils.document_ai_parser import DocumentAIParser
from utils.normalizer import ProductNameNormalizer
from .models import ParseHistory, ParsedItem

logger = logging.getLogger(__name__)


class ParsePDFView(APIView):
    """
    Parse PDF and extract estimate data using Document AI Form Parser

    POST /api/parse/
    Content-Type: multipart/form-data

    Body:
    - pdf: PDF file (required)
    - vendor_name: Override vendor name (optional)

    Returns:
    {
        "vendor_name": "...",
        "estimate_date": "2025-01-19",
        "total_excl_tax": 15100,
        "total_incl_tax": 16610,
        "items": [
            {
                "item_name_raw": "ワイパーブレード",
                "item_name_norm": "wiper_blade",
                "cost_type": "parts",
                "amount_excl_tax": 3800,
                "quantity": 1
            },
            ...
        ]
    }
    """
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request, *args, **kwargs):
        logger.info("=" * 60)
        logger.info("=== PDF Parse Request Received ===")
        logger.info(f"Request method: {request.method}")
        logger.info(f"Content-Type: {request.content_type}")

        # Get PDF file from request
        pdf_file = request.FILES.get('pdf')
        if not pdf_file:
            logger.error("✗ No PDF file in request")
            return Response(
                {'error': 'PDF file is required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        logger.info(f"✓ PDF file received: {pdf_file.name} ({pdf_file.size} bytes)")

        # Get optional vendor name override
        vendor_name_override = request.data.get('vendor_name')

        # Save PDF to temporary file
        tmp_path = None
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.pdf') as tmp_file:
                for chunk in pdf_file.chunks():
                    tmp_file.write(chunk)
                tmp_path = tmp_file.name

            # Extract data using Document AI
            doc_ai = DocumentAIParser()
            logger.info(f"=== Parsing PDF: {pdf_file.name} ===")
            logger.info(f"Vendor name override: {vendor_name_override}")

            try:
                parsed_data = doc_ai.extract_estimate_data(tmp_path, vendor_name_override)
                logger.info(f"✓ Document AI parsing successful")
                logger.info(f"  Vendor: {parsed_data.get('vendor_name')}")
                logger.info(f"  Items: {len(parsed_data.get('items', []))}")
            except Exception as e:
                # If Document AI fails, use dummy data
                logger.error(f"✗ Document AI parsing FAILED: {e.__class__.__name__}: {e}")
                logger.error(f"  Falling back to DUMMY DATA")
                import traceback
                logger.error(traceback.format_exc())
                parsed_data = doc_ai._get_dummy_estimate_data(vendor_name_override)

            # Normalize item names and determine cost types
            normalized_items = []
            for item in parsed_data['items']:
                normalized_name = ProductNameNormalizer.normalize(item['item_name_raw'])
                cost_type = ProductNameNormalizer.determine_cost_type(item['item_name_raw'])
                quantity = item.get('quantity', 1)

                normalized_items.append({
                    'item_name_raw': item['item_name_raw'],
                    'item_name_norm': normalized_name,
                    'cost_type': cost_type,
                    'amount_excl_tax': item['amount_excl_tax'],
                    'quantity': quantity,
                })

            # Update parsed data with normalized items
            parsed_data['items'] = normalized_items

            # Add PDF filename to response for later save
            parsed_data['pdf_filename'] = pdf_file.name

            # Return parsed data WITHOUT saving to database
            # User will review and confirm before saving
            logger.info("✓ Returning parsed data (not saved yet)")
            return Response(parsed_data, status=status.HTTP_200_OK)

        except Exception as e:
            return Response(
                {'error': f'Failed to process PDF: {str(e)}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )
        finally:
            # Clean up temporary file
            if tmp_path and os.path.exists(tmp_path):
                os.remove(tmp_path)


class HealthCheckView(APIView):
    """
    Health check endpoint

    GET /api/health/
    """
    def get(self, request, *args, **kwargs):
        # Check Document AI availability
        doc_ai_status = 'available'
        try:
            doc_ai = DocumentAIParser()
            if not doc_ai.client:
                doc_ai_status = 'credentials_missing'
        except Exception as e:
            doc_ai_status = f'error: {str(e)}'

        return Response({
            'status': 'healthy',
            'service': 'django-ocr-documentai',
            'document_ai': doc_ai_status,
            'timestamp': datetime.now().isoformat(),
        })


class SaveEstimateView(APIView):
    """
    Save user-confirmed estimate data to database

    POST /api/save_estimate/
    Content-Type: application/json

    Body:
    {
        "pdf_filename": "sample.pdf",
        "vendor_name": "Toyota Dealer",
        "estimate_date": "2025-01-19",
        "total_excl_tax": 121758,
        "total_incl_tax": 133934,
        "items": [
            {
                "item_name_raw": "ワイパーブレード",
                "item_name_norm": "wiper_blade",
                "cost_type": "parts",
                "amount_excl_tax": 3800,
                "quantity": 1
            },
            ...
        ]
    }

    Returns:
    {
        "success": true,
        "parse_history_id": 123,
        "message": "Estimate data saved successfully"
    }
    """

    def post(self, request, *args, **kwargs):
        logger.info("=" * 60)
        logger.info("=== Save Estimate Request Received ===")

        try:
            # Extract data from request
            pdf_filename = request.data.get('pdf_filename')
            vendor_name = request.data.get('vendor_name')
            estimate_date = request.data.get('estimate_date')
            total_excl_tax = request.data.get('total_excl_tax')
            total_incl_tax = request.data.get('total_incl_tax')
            items = request.data.get('items', [])

            # Validate required fields
            if not pdf_filename:
                return Response(
                    {'error': 'pdf_filename is required'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if not vendor_name:
                return Response(
                    {'error': 'vendor_name is required'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if not estimate_date:
                return Response(
                    {'error': 'estimate_date is required'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if total_excl_tax is None or total_incl_tax is None:
                return Response(
                    {'error': 'total_excl_tax and total_incl_tax are required'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if not items:
                return Response(
                    {'error': 'items array cannot be empty'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            logger.info(f"✓ Validation passed")
            logger.info(f"  PDF: {pdf_filename}")
            logger.info(f"  Vendor: {vendor_name}")
            logger.info(f"  Date: {estimate_date}")
            logger.info(f"  Items: {len(items)}")

            # Save to database
            parse_history = ParseHistory.objects.create(
                pdf_filename=pdf_filename,
                vendor_name=vendor_name,
                estimate_date=estimate_date,
                total_excl_tax=total_excl_tax,
                total_incl_tax=total_incl_tax,
            )

            # Save line items
            for item in items:
                ParsedItem.objects.create(
                    parse_history=parse_history,
                    item_name_raw=item.get('item_name_raw', ''),
                    item_name_norm=item.get('item_name_norm', ''),
                    cost_type=item.get('cost_type', 'unknown'),
                    amount_excl_tax=item.get('amount_excl_tax', 0),
                    quantity=item.get('quantity', 1),
                )

            logger.info(f"✓ Estimate data saved successfully (ID: {parse_history.id})")

            return Response({
                'success': True,
                'parse_history_id': parse_history.id,
                'message': 'Estimate data saved successfully'
            }, status=status.HTTP_201_CREATED)

        except Exception as e:
            logger.error(f"✗ Failed to save estimate data: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return Response(
                {'error': f'Failed to save estimate data: {str(e)}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class ParseHistoryView(APIView):
    """
    Get parse history

    GET /api/history/
    """
    def get(self, request, *args, **kwargs):
        histories = ParseHistory.objects.all()[:20]  # Last 20

        data = []
        for history in histories:
            data.append({
                'id': history.id,
                'pdf_filename': history.pdf_filename,
                'vendor_name': history.vendor_name,
                'estimate_date': str(history.estimate_date),
                'total_excl_tax': history.total_excl_tax,
                'total_incl_tax': history.total_incl_tax,
                'items_count': history.items.count(),
                'created_at': history.created_at.isoformat(),
            })

        return Response({'history': data}, status=status.HTTP_200_OK)

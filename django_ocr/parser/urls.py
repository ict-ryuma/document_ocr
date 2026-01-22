"""
URL patterns for parser API
"""
from django.urls import path
from .views import ParsePDFView, HealthCheckView, ParseHistoryView, SaveEstimateView

urlpatterns = [
    path('parse/', ParsePDFView.as_view(), name='parse_pdf'),
    path('save_estimate/', SaveEstimateView.as_view(), name='save_estimate'),
    path('health/', HealthCheckView.as_view(), name='health_check'),
    path('history/', ParseHistoryView.as_view(), name='parse_history'),
]

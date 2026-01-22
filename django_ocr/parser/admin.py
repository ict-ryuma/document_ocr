"""
Django admin configuration
"""
from django.contrib import admin
from .models import ParseHistory, ParsedItem


@admin.register(ParseHistory)
class ParseHistoryAdmin(admin.ModelAdmin):
    list_display = ['id', 'vendor_name', 'estimate_date', 'total_incl_tax', 'pdf_filename', 'created_at']
    list_filter = ['vendor_name', 'estimate_date', 'created_at']
    search_fields = ['vendor_name', 'pdf_filename']
    readonly_fields = ['created_at', 'updated_at']


@admin.register(ParsedItem)
class ParsedItemAdmin(admin.ModelAdmin):
    list_display = ['id', 'parse_history', 'item_name_norm', 'item_name_raw', 'cost_type', 'amount_excl_tax']
    list_filter = ['cost_type', 'item_name_norm']
    search_fields = ['item_name_raw', 'item_name_norm']

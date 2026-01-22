"""
Django models for parser history
"""
from django.db import models


class ParseHistory(models.Model):
    """
    Store PDF parsing history and results
    """
    pdf_filename = models.CharField(max_length=255)
    vendor_name = models.CharField(max_length=255)
    estimate_date = models.DateField()
    total_excl_tax = models.IntegerField(default=0)
    total_incl_tax = models.IntegerField(default=0)
    raw_ocr_text = models.TextField(blank=True)
    parsed_json = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'parse_history'
        ordering = ['-created_at']
        verbose_name = 'Parse History'
        verbose_name_plural = 'Parse Histories'

    def __str__(self):
        return f"{self.vendor_name} - {self.estimate_date} - {self.pdf_filename}"


class ParsedItem(models.Model):
    """
    Individual items from parsed estimates
    """
    parse_history = models.ForeignKey(
        ParseHistory,
        on_delete=models.CASCADE,
        related_name='items'
    )
    item_name_raw = models.CharField(max_length=255)
    item_name_norm = models.CharField(max_length=100)
    cost_type = models.CharField(
        max_length=20,
        choices=[
            ('parts', 'Parts'),
            ('labor', 'Labor'),
        ],
        default='parts'
    )
    amount_excl_tax = models.IntegerField(default=0)
    quantity = models.IntegerField(default=1)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'parsed_items'
        ordering = ['id']

    def __str__(self):
        return f"{self.item_name_norm} ({self.item_name_raw})"

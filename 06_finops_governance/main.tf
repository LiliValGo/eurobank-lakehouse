# Obtener automáticamente el contexto de la suscripción activa
data "azurerm_subscription" "current" {}

resource "azurerm_consumption_budget_subscription" "eurobank_budget" {
  name            = "budget-subscription-limit"
  subscription_id = data.azurerm_subscription.current.id

  amount     = var.budget_amount
  time_grain = "Monthly"

  time_period {
    # Se inicia el primer día del mes actual
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
    # Opcional: vigencia a un año vista
    end_date   = formatdate("YYYY-MM-01'T'00:00:00'Z'", timeadd(timestamp(), "8760h"))
  }

  lifecycle {
    ignore_changes = [
      time_period[0].start_date
    ]
  }

  # Alerta temprana: 50% de gasto real (2.50 USD)
  notification {
    enabled        = true
    threshold      = 50.0
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.notification_emails
  }

  # Alerta preventiva: 80% de gasto real (4.00 USD)
  notification {
    enabled        = true
    threshold      = 80.0
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.notification_emails
  }

  # Alerta crítica: 100% de gasto real alcanzado (5.00 USD)
  notification {
    enabled        = true
    threshold      = 100.0
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.notification_emails
  }

  # Alerta predictiva: Proyección que prevé exceder el 100% a fin de mes
  notification {
    enabled        = true
    threshold      = 100.0
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = var.notification_emails
  }
}

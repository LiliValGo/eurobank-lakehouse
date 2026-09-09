output "budget_id" {
  description = "ID del presupuesto creado en Azure"
  value       = azurerm_consumption_budget_subscription.eurobank_budget.id
}

output "budget_amount" {
  description = "Importe mensual límite configurado"
  value       = azurerm_consumption_budget_subscription.eurobank_budget.amount
}

output "subscription_id" {
  description = "ID de la suscripción donde se aplicó el presupuesto"
  value       = data.azurerm_subscription.current.subscription_id
}

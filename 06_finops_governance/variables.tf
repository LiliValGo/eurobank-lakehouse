variable "budget_amount" {
  type        = number
  description = "Límite máximo del presupuesto en la moneda de facturación de la suscripción (ej. 5 USD)"
  default     = 5.0
}

variable "notification_emails" {
  type        = list(string)
  description = "Lista de correos electrónicos a los que se enviarán las alertas"
}

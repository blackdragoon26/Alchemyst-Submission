output "gateway_public_ip" {
  value = aws_eip.gateway.public_ip
}

output "engine_private_ip" {
  value = aws_instance.engine.private_ip
}

output "math_worker_private_ip" {
  value = aws_instance.math_worker.private_ip
}

output "caller_worker_private_ip" {
  value = aws_instance.caller_worker.private_ip
}

output "curl_command" {
  value = "curl -X POST http://${aws_eip.gateway.public_ip}/math/add-two-numbers -H 'Content-Type: application/json' -d '{\"a\": 10, \"b\": 20}'"
}

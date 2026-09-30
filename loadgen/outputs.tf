output "loadgen_public_ip" {
  value = aws_instance.loadgen.public_ip
}

output "loadgen_instance_id" {
  value = aws_instance.loadgen.id
}

output "karpenter_controller_role_arn" {
  value = aws_iam_role.karpenter_controller.arn
}

output "karpenter_node_role_name" {
  value = aws_iam_role.karpenter_node.name
}

output "karpenter_interruption_queue_name" {
  value = aws_sqs_queue.karpenter.name
}

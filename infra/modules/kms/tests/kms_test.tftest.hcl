mock_provider "aws" {}

run "valid_key" {
  command = plan

  variables {
    description             = "Test KMS key"
    deletion_window_in_days = 10
    alias_name              = "alias/chatbot-test"
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true
    error_message = "enable_key_rotation debe ser true"
  }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days >= 7 && aws_kms_key.this.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days fuera de rango 7-30"
  }

  assert {
    condition     = startswith(aws_kms_alias.this.name, "alias/")
    error_message = "El alias debe comenzar con 'alias/'"
  }
}

run "invalid_window" {
  command = plan

  variables {
    description             = "Test KMS key"
    deletion_window_in_days = 5
    alias_name              = "alias/chatbot-test"
  }

  expect_failures = [var.deletion_window_in_days]
}

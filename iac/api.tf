resource "aws_apigatewayv2_api" "main" {
  name          = "${local.prefix}-api"
  description   = "${local.prefix} HTTP API"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["content-type", "authorization", "x-amz-date", "x-api-key"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_origins = ["https://${var.domain_name}"]
    max_age       = 3600
  }
  tags = local.common_tags
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito"
  jwt_configuration {
    audience = [module.cognito.client_id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${module.cognito.user_pool_id}"
  }
}

resource "aws_apigatewayv2_authorizer" "access_token" {
  api_id                            = aws_apigatewayv2_api.main.id
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = module.lambda.invoke_arns["token_authorizer"]
  identity_sources                  = ["$request.header.Authorization"]
  name                              = "${local.prefix}-access-token"
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = false
  authorizer_result_ttl_in_seconds  = 300
}

resource "aws_apigatewayv2_integration" "api_handler" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = module.lambda.invoke_arns["api_handler"]
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "oem_cmd" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = module.lambda.invoke_arns["oem_command_proxy"]
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "token_gen" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = module.lambda.invoke_arns["token_generator"]
  payload_format_version = "2.0"
}

locals {
  apigw_routes = {
    auth = {
      key    = "ANY /auth/{proxy+}"
      target = aws_apigatewayv2_integration.api_handler.id
      auth   = null
    }
    oem_login = {
      key    = "GET /oem/login"
      target = aws_apigatewayv2_integration.api_handler.id
      auth   = null
    }
    oem_callback = {
      key    = "GET /oem/callback"
      target = aws_apigatewayv2_integration.api_handler.id
      auth   = null
    }
    oem = {
      key    = "ANY /oem/{proxy+}"
      target = aws_apigatewayv2_integration.oem_cmd.id
      auth   = "jwt"
    }
    trip_token = {
      key    = "GET /api/trips/{tripId}/token"
      target = aws_apigatewayv2_integration.token_gen.id
      auth   = "jwt"
    }
    dashcam_signed_url = {
      key    = "GET /api/dashcam/{eventId}/signed-url"
      target = aws_apigatewayv2_integration.token_gen.id
      auth   = "jwt"
    }
    trip_data = {
      key    = "GET /api/trips/{tripId}"
      target = aws_apigatewayv2_integration.api_handler.id
      auth   = "custom"
    }
    trip_breadcrumbs = {
      key    = "GET /api/trips/{tripId}/breadcrumbs"
      target = aws_apigatewayv2_integration.api_handler.id
      auth   = "custom"
    }
    trip_replay = {
      key    = "GET /api/trips/{tripId}/replay"
      target = aws_apigatewayv2_integration.api_handler.id
      auth   = "custom"
    }
    dashcam_event = {
      key    = "GET /api/dashcam/{eventId}"
      target = aws_apigatewayv2_integration.api_handler.id
      auth   = "custom"
    }
    api_catchall = {
      key    = "ANY /api/{proxy+}"
      target = aws_apigatewayv2_integration.api_handler.id
      auth   = "jwt"
    }
  }
}

resource "aws_apigatewayv2_route" "routes" {
  for_each = local.apigw_routes

  api_id    = aws_apigatewayv2_api.main.id
  route_key = each.value.key
  target    = "integrations/${each.value.target}"

  authorization_type = each.value.auth == "jwt" ? "JWT" : each.value.auth == "custom" ? "CUSTOM" : null
  authorizer_id      = each.value.auth == "jwt" ? aws_apigatewayv2_authorizer.cognito.id : each.value.auth == "custom" ? aws_apigatewayv2_authorizer.access_token.id : null
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
    })
  }
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigateway/${local.prefix}-api"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_lambda_permission" "apigw_api_handler" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.function_arns["api_handler"]
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_oem_command_proxy" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.function_arns["oem_command_proxy"]
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_token_authorizer" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.function_arns["token_authorizer"]
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.access_token.id}"
}

resource "aws_lambda_permission" "apigw_token_generator" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.function_arns["token_generator"]
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

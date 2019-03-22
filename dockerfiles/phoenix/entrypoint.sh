#!/bin/bash

export AWS_DEFAULT_REGION=ap-northeast-1

myaws ssm parameter get pleroma.$SERVICE_ENV.db_host --region $AWS_DEFAULT_REGION
ret=$?
if [[ $ret -ne 0 ]]; then
    exit
fi

export RELX_REPLACE_OS_VARS=true
export SECRET_KEY_BASE=`myaws ssm parameter get pleroma.$SERVICE_ENV.secret_key_base --region $AWS_DEFAULT_REGION`
export SLACK_WEBHOOK_URL=`myaws ssm parameter get pleroma.$SERVICE_ENV.slack_webhook_url --region $AWS_DEFAULT_REGION`
export DB_USER=`myaws ssm parameter get pleroma.$SERVICE_ENV.db_user --region $AWS_DEFAULT_REGION`
export DB_PASSWORD=`myaws ssm parameter get pleroma.$SERVICE_ENV.db_password --region $AWS_DEFAULT_REGION`
export DB_NAME=`myaws ssm parameter get pleroma.$SERVICE_ENV.db_name --region $AWS_DEFAULT_REGION`
export DB_HOST=`myaws ssm parameter get pleroma.$SERVICE_ENV.db_host --region $AWS_DEFAULT_REGION`
export S3_BUCKET=`myaws ssm parameter get pleroma.$SERVICE_ENV.s3_bucket --region $AWS_DEFAULT_REGION`
export WEB_PUSH_PUBLIC_KEY=`myaws ssm parameter get pleroma.$SERVICE_ENV.web_push_public_key --region $AWS_DEFAULT_REGION`
export WEB_PUSH_PRIVATE_KEY=`myaws ssm parameter get pleroma.$SERVICE_ENV.web_push_private_key --region $AWS_DEFAULT_REGION`

exec "$@"

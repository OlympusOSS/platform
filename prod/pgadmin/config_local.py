import os

AUTHENTICATION_SOURCES = ['oauth2']

# Security fix (platform#21 — OWASP A01:2021 Broken Access Control):
# OAUTH2_AUTO_CREATE_USER = False prevents pgAdmin from silently provisioning
# a new database admin account for every IAM identity that successfully
# authenticates via IAM Hydra. Only pre-provisioned DBA accounts may log in.
OAUTH2_AUTO_CREATE_USER = False

# Role-based access validation (platform#21 — mandatory defense-in-depth layer):
# Even for pre-provisioned accounts, the IAM identity must hold the 'dba' role.
# The 'roles' claim is injected into the ID token by the IAM Hydra Jsonnet claims
# mapper configured on the pgAdmin OAuth2 client. If the claim is absent, null,
# or does not contain 'dba', access is denied at the application layer.
# This provides a second enforcement layer independent of pgAdmin's user database.
OAUTH2_ADDITIONAL_CLAIMS_VALIDATION = {
    'roles': lambda roles: 'dba' in (roles or [])
}

OAUTH2_CONFIG = [
    {
        'OAUTH2_NAME': 'olympus',
        'OAUTH2_DISPLAY_NAME': 'Olympus',
        'OAUTH2_CLIENT_ID': os.environ.get('PGADMIN_OAUTH_CLIENT_ID', 'pgadmin'),
        'OAUTH2_CLIENT_SECRET': os.environ.get('PGADMIN_OAUTH_CLIENT_SECRET', ''),
        'OAUTH2_TOKEN_URL': 'http://iam-hydra:7002/oauth2/token',
        'OAUTH2_AUTHORIZATION_URL': os.environ.get('IAM_HYDRA_PUBLIC_URL', '') + '/oauth2/auth',
        'OAUTH2_SERVER_METADATA_URL': 'http://iam-hydra:7002/.well-known/openid-configuration',
        'OAUTH2_API_BASE_URL': 'http://iam-hydra:7002/',
        'OAUTH2_USERINFO_ENDPOINT': 'userinfo',
        'OAUTH2_SCOPE': 'openid email profile',
        'OAUTH2_ICON': 'fa-shield',
        'OAUTH2_BUTTON_COLOR': '#6366f1',
    }
]

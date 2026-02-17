import os

AUTHENTICATION_SOURCES = ['oauth2', 'internal']

OAUTH2_AUTO_CREATE_USER = True

OAUTH2_CONFIG = [
    {
        'OAUTH2_NAME': 'athena',
        'OAUTH2_DISPLAY_NAME': 'Athena SSO',
        'OAUTH2_CLIENT_ID': 'pgadmin',
        'OAUTH2_CLIENT_SECRET': 'pgadmin-secret',
        'OAUTH2_TOKEN_URL': 'http://iam-hydra:7002/oauth2/token',
        'OAUTH2_AUTHORIZATION_URL': 'http://localhost:4102/oauth2/auth',
        'OAUTH2_API_BASE_URL': 'http://iam-hydra:7002/',
        'OAUTH2_USERINFO_ENDPOINT': 'userinfo',
        'OAUTH2_SCOPE': 'openid email profile',
        'OAUTH2_ICON': 'fa-shield',
        'OAUTH2_BUTTON_COLOR': '#6366f1',
    }
]

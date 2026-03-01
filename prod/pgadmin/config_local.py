import os

AUTHENTICATION_SOURCES = ['oauth2']

OAUTH2_AUTO_CREATE_USER = True

OAUTH2_CONFIG = [
    {
        'OAUTH2_NAME': 'olympus',
        'OAUTH2_DISPLAY_NAME': 'Login with Olympus',
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

#
# Copyright (c) 2024 Airbyte, Inc., all rights reserved.
#

from unittest.mock import MagicMock, patch

from source_acumatica.source import SourceAcumatica


def test_check_connection_success(mocker):
    source = SourceAcumatica()
    logger_mock = MagicMock()
    config = {
        "BASEURL": "https://example.acumatica.com",
        "CLIENTID": "test-client-id",
        "CLIENTSECRET": "test-client-secret",
        "USERNAME": "testuser",
        "PASSWORD": "testpass",
    }
    mock_auth = MagicMock()
    mock_auth.get_access_token.return_value = "fake-token"
    mocker.patch("source_acumatica.source.AcumaticaOauth2Authenticator", return_value=mock_auth)
    assert source.check_connection(logger_mock, config) == (True, None)


def test_check_connection_failure(mocker):
    source = SourceAcumatica()
    logger_mock = MagicMock()
    config = {
        "BASEURL": "https://example.acumatica.com",
        "CLIENTID": "test-client-id",
        "CLIENTSECRET": "test-client-secret",
        "USERNAME": "testuser",
        "PASSWORD": "testpass",
    }
    mock_auth = MagicMock()
    mock_auth.get_access_token.side_effect = Exception("Invalid credentials")
    mocker.patch("source_acumatica.source.AcumaticaOauth2Authenticator", return_value=mock_auth)
    ok, error = source.check_connection(logger_mock, config)
    assert ok is False
    assert "Invalid credentials" in error

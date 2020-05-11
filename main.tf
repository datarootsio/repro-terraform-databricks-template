provider "azurerm" {
  version = "~> 2.6.0"
  features {}
}

provider "azuread" {
  version = "~> 0.8.0"
}

data "azurerm_client_config" "current" {
}


resource "azuread_application" "aadapp" {
  name = "app-repro"
  required_resource_access {
    resource_app_id = "e406a681-f3d4-42a8-90b6-c2b029497af1"
    resource_access {
      id   = "03e0da56-190b-40ad-a80c-ea378c433f7f"
      type = "Scope"
    }
  }
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000"
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
      type = "Scope"
    }
  }
}

resource "random_password" "aadapp_secret" {
  length = 32
}

resource "azuread_service_principal" "sp" {
  application_id = azuread_application.aadapp.application_id
}

resource "azuread_service_principal_password" "sppw" {
  service_principal_id = azuread_service_principal.sp.id
  value                = random_password.aadapp_secret.result
  end_date             = "2021-01-01T00:00:00Z"
}

resource "azurerm_resource_group" "rg" {
  name     = "rgrepro"
  location = "eastus2"
}

resource "azurerm_role_assignment" "sprg" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Owner"
  principal_id         = azuread_service_principal.sp.object_id
}

resource "azurerm_storage_account" "sample" {
  name                     = "sasamplerepro"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  access_tier              = "Hot"
  account_replication_type = "LRS"
}

resource "azurerm_role_assignment" "current_user_sa_dbks" {
  scope                = azurerm_storage_account.sample.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "spsa_sa_dbks" {
  scope                = azurerm_storage_account.sample.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azuread_service_principal.sp.id
}

resource "azurerm_storage_container" "databricks" {
  name                 = "databricks"
  storage_account_name = azurerm_storage_account.sample.name
}

resource "azurerm_databricks_workspace" "dbks" {
  name                        = "dbksrepro"
  resource_group_name         = azurerm_resource_group.rg.name
  managed_resource_group_name = "rgdbksrepro"
  location                    = azurerm_resource_group.rg.location
  sku                         = "standard"
}

provider "databricks" {
  azure_auth = {
    managed_resource_group = azurerm_databricks_workspace.dbks.managed_resource_group_name
    azure_region           = azurerm_databricks_workspace.dbks.location
    workspace_name         = azurerm_databricks_workspace.dbks.name
    resource_group         = azurerm_databricks_workspace.dbks.resource_group_name
    client_id              = azuread_application.aadapp.application_id
    client_secret          = random_password.aadapp_secret.result
    tenant_id              = data.azurerm_client_config.current.tenant_id
    subscription_id        = data.azurerm_client_config.current.subscription_id
  }
}

resource "databricks_notebook" "spark_setup" {
  content   = base64encode(templatefile("${path.module}/spark_setup.scala", { blob_host = azurerm_storage_account.sample.primary_blob_host }))
  language  = "SCALA"
  path      = "/Shared/spark_setup.scala"
  overwrite = false
  mkdirs    = true
  format    = "SOURCE"
}
// MSAL Configuration
// Replace these values with your Azure AD app registration details
const msalConfig = {
    auth: {
        clientId: "36557ed5-4588-4f5f-ac79-b2b19231b8a2", // Application (client) ID from Azure Portal
        authority: "https://login.microsoftonline.com/5847dfca-ef81-4bdf-a530-daae8b3c2974", // Single tenant - only your organization
        redirectUri: window.location.origin + "/index.html" // Must match registered redirect URI
    },
    cache: {
        cacheLocation: "sessionStorage", // Options: "sessionStorage" or "localStorage"
        storeAuthStateInCookie: false
    }
};

// Scopes for the access token
const loginRequest = {
    scopes: ["User.Read", "openid", "profile"]
};

// API Configuration (if you have a backend API)
const apiConfig = {
    // Replace with your API endpoint
    baseUrl: "https://your-api-endpoint.azurewebsites.net/api",
    endpoints: {
        tenants: "/tenants",
        runReport: "/reports/run",
        reconsent: "/tenants/reconsent",
        removeTenant: "/tenants/remove"
    }
};

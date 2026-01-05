# Cyber Essentials Report - Web Application

A modern web application for managing tenants and generating Cyber Essentials reports, integrated with Microsoft Entra ID (formerly Azure Active Directory) for authentication.

## Features

- ✅ **Microsoft Entra ID Authentication** - Secure sign-in using Microsoft accounts
- ✅ **Tenant Management** - View, add, and remove tenants
- ✅ **Report Generation** - Run Cyber Essentials reports for selected tenants
- ✅ **Reconsent Flow** - Initiate reconsent process for tenant permissions
- ✅ **Responsive Design** - Works seamlessly on desktop and mobile devices
- ✅ **Modern UI** - Clean and professional interface

## Prerequisites

Before you begin, ensure you have:

1. **Azure Subscription** - An active Azure account
2. **App Registration** - A registered application in Microsoft Entra ID
3. **Web Server** - A local or hosted web server to serve the application

## Setup Instructions

### Step 1: Register Your Application in Azure

1. Go to the [Azure Portal](https://portal.azure.com)
2. Navigate to **Microsoft Entra ID** > **App registrations**
3. Click **+ New registration**
4. Fill in the registration form:
   - **Name**: Cyber Essentials Report App
   - **Supported account types**: Choose based on your needs
     - Single tenant: Only your organization
     - Multi-tenant: Any Microsoft Entra ID tenant
   - **Redirect URI**: 
     - Platform: Single-page application (SPA)
     - URI: `http://localhost:8080/index.html` (update for production)
5. Click **Register**

### Step 2: Configure API Permissions

1. In your app registration, go to **API permissions**
2. Click **+ Add a permission**
3. Select **Microsoft Graph**
4. Add these **Delegated permissions**:
   - `User.Read` - Read user profile
   - `openid` - Sign in
   - `profile` - View user's basic profile
5. Click **Add permissions**
6. (Optional) Click **Grant admin consent** if you have admin rights

### Step 3: Configure the Application

1. Copy your **Application (client) ID** from the app registration overview
2. Open `config.js` in your project
3. Update the configuration:

```javascript
const msalConfig = {
    auth: {
        clientId: "YOUR_CLIENT_ID_HERE", // Replace with your Application ID
        authority: "https://login.microsoftonline.com/common", // Or your tenant ID
        redirectUri: "http://localhost:8080/index.html" // Match your redirect URI
    },
    cache: {
        cacheLocation: "sessionStorage",
        storeAuthStateInCookie: false
    }
};
```

**Authority Options:**
- `common` - Multi-tenant (personal and work accounts)
- `organizations` - Work/school accounts only
- `consumers` - Personal Microsoft accounts only
- `{tenant-id}` - Specific organization only

### Step 4: Configure Backend API (Optional)

If you have a backend API:

1. Update the `apiConfig` in `config.js`:

```javascript
const apiConfig = {
    baseUrl: "https://your-api-endpoint.azurewebsites.net/api",
    endpoints: {
        tenants: "/tenants",
        runReport: "/reports/run",
        reconsent: "/tenants/reconsent",
        removeTenant: "/tenants/remove"
    }
};
```

2. Uncomment the API call code in `app.js`
3. Ensure your backend API validates the access tokens

## Running the Application

### Option 1: Using Python HTTP Server

```bash
# Navigate to the WebApp directory
cd "c:\Users\deeptha.madhuranga\OneDrive - Infinity Group\Scripts\Cyber Essentials Report\WebApp"

# Start Python HTTP server
python -m http.server 8080
```

Then open your browser to `http://localhost:8080`

### Option 2: Using Node.js http-server

```bash
# Install http-server globally (one time)
npm install -g http-server

# Navigate to the WebApp directory
cd "c:\Users\deeptha.madhuranga\OneDrive - Infinity Group\Scripts\Cyber Essentials Report\WebApp"

# Start the server
http-server -p 8080
```

Then open your browser to `http://localhost:8080`

### Option 3: Using Visual Studio Code Live Server

1. Install the "Live Server" extension in VS Code
2. Right-click on `index.html`
3. Select "Open with Live Server"

## File Structure

```
WebApp/
├── index.html      # Main HTML structure
├── styles.css      # CSS styling
├── config.js       # MSAL and API configuration
├── auth.js         # Authentication logic (MSAL)
├── app.js          # Application logic and UI handlers
└── README.md       # This file
```

## How to Use

### 1. Sign In
- Click the **"Sign in with Microsoft"** button
- You'll be redirected to Microsoft's login page
- Enter your credentials and consent to permissions
- You'll be redirected back to the application

### 2. View Tenants
- After signing in, you'll see a list of tenants
- Use the search box to filter tenants
- Click on a tenant to view details

### 3. Manage Tenants

**Add a Tenant:**
1. Click **"+ Add Tenant"**
2. Enter tenant name, ID (GUID), and domain
3. Click **"Add Tenant"**

**Select a Tenant:**
- Click on any tenant in the list to view details and actions

**Available Actions:**
- 📊 **Run Report** - Generate a Cyber Essentials report
- 🔄 **Reconsent** - Initiate permission reconsent
- 🗑️ **Remove Tenant** - Delete the tenant (with confirmation)

## Integrating with Your Backend

The current implementation uses sample data. To integrate with a real backend:

1. **Uncomment API Calls**: In `app.js`, uncomment the fetch calls in:
   - `runReport()`
   - `reconsentTenant()`
   - `removeTenant()`
   - `addTenant()`
   - `loadTenants()` (you'll need to add this)

2. **Backend Requirements**: Your API should:
   - Validate Azure AD access tokens
   - Implement endpoints matching `apiConfig.endpoints`
   - Return appropriate JSON responses
   - Handle CORS if hosted on different domain

3. **Example Backend Call**:
```javascript
const token = await window.authModule.getAccessToken();
const response = await fetch(`${apiConfig.baseUrl}/tenants`, {
    headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
    }
});
const data = await response.json();
```

## Security Considerations

1. **Never commit secrets** to version control
2. **Use HTTPS** in production
3. **Validate tokens** on the backend
4. **Implement proper CORS** policies
5. **Use environment-specific** configurations
6. **Enable audit logging** for tenant operations
7. **Implement rate limiting** on API endpoints

## Troubleshooting

### "AADSTS50011: The redirect URI specified in the request does not match"
- Ensure the redirect URI in `config.js` matches exactly what's registered in Azure Portal
- Include the protocol (http/https) and full path

### "User not signed in" errors
- Check browser console for errors
- Verify clientId is correct
- Check if cookies/local storage are enabled

### CORS errors
- Ensure your backend API has proper CORS configuration
- Allow your web app's origin in the CORS policy

### Authentication loop
- Clear browser cache and cookies
- Check if the authority URL is correct
- Verify the app has proper permissions

## Production Deployment

Before deploying to production:

1. **Update Redirect URIs** in Azure Portal with production URLs
2. **Enable HTTPS** - Required for production
3. **Update config.js** with production values
4. **Minimize JavaScript** files for performance
5. **Set up monitoring** and logging
6. **Implement error tracking** (e.g., Application Insights)
7. **Add loading states** and better error handling
8. **Test thoroughly** with real users

## Additional Resources

- [MSAL.js Documentation](https://learn.microsoft.com/entra/identity-platform/tutorial-v2-javascript-spa)
- [Microsoft Entra ID Documentation](https://learn.microsoft.com/entra/identity/)
- [Azure App Registration Guide](https://learn.microsoft.com/entra/identity-platform/quickstart-register-app)
- [Microsoft Graph API](https://learn.microsoft.com/graph/overview)

## Support

For issues or questions:
1. Check the browser console for error messages
2. Review Azure AD sign-in logs in the Azure Portal
3. Verify all configuration values are correct

## License

Copyright © 2026 - Cyber Essentials Report Application

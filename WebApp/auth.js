// Initialize MSAL
const msalInstance = new msal.PublicClientApplication(msalConfig);

let currentAccount = null;

// Authentication Functions
async function initializeAuth() {
    try {
        // Handle redirect promise
        const response = await msalInstance.handleRedirectPromise();
        
        if (response) {
            currentAccount = response.account;
            showDashboard();
        } else {
            // Check if user is already logged in
            const accounts = msalInstance.getAllAccounts();
            if (accounts.length > 0) {
                currentAccount = accounts[0];
                showDashboard();
            } else {
                showSignIn();
            }
        }
    } catch (error) {
        console.error('Auth initialization error:', error);
        showError('Authentication initialization failed. Please refresh the page.');
    }
}

async function signIn() {
    try {
        // Use redirect for sign in
        await msalInstance.loginRedirect(loginRequest);
    } catch (error) {
        console.error('Sign in error:', error);
        showError('Sign in failed: ' + error.message);
    }
}

async function signOut() {
    try {
        const logoutRequest = {
            account: currentAccount
        };
        await msalInstance.logoutRedirect(logoutRequest);
    } catch (error) {
        console.error('Sign out error:', error);
        showError('Sign out failed: ' + error.message);
    }
}

async function getAccessToken() {
    if (!currentAccount) {
        throw new Error('No user account found');
    }

    const request = {
        scopes: loginRequest.scopes,
        account: currentAccount
    };

    try {
        // Try to acquire token silently
        const response = await msalInstance.acquireTokenSilent(request);
        return response.accessToken;
    } catch (error) {
        if (error instanceof msal.InteractionRequiredAuthError) {
            // If silent acquisition fails, use redirect
            return msalInstance.acquireTokenRedirect(request);
        }
        throw error;
    }
}

// UI State Functions
function showSignIn() {
    document.getElementById('signinSection').style.display = 'block';
    document.getElementById('dashboardSection').style.display = 'none';
}

function showDashboard() {
    document.getElementById('signinSection').style.display = 'none';
    document.getElementById('dashboardSection').style.display = 'block';
    
    if (currentAccount) {
        document.getElementById('userName').textContent = currentAccount.name || currentAccount.username;
    }
    
    // Load tenants
    loadTenants();
}

function showError(message) {
    const errorElement = document.getElementById('errorMessage');
    errorElement.textContent = message;
    errorElement.style.display = 'block';
    
    setTimeout(() => {
        errorElement.style.display = 'none';
    }, 5000);
}

// Event Listeners
document.addEventListener('DOMContentLoaded', () => {
    // Initialize authentication
    initializeAuth();
    
    // Sign in button
    const signInButton = document.getElementById('signInButton');
    if (signInButton) {
        signInButton.addEventListener('click', signIn);
    }
    
    // Sign out button
    const signOutButton = document.getElementById('signOutButton');
    if (signOutButton) {
        signOutButton.addEventListener('click', signOut);
    }
});

// Export functions for use in app.js
window.authModule = {
    getAccessToken,
    getCurrentUser: () => currentAccount,
    isAuthenticated: () => currentAccount !== null
};

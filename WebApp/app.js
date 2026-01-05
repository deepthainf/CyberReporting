// Sample tenant data (replace with actual API calls)
let tenants = [
    {
        id: "1",
        tenantId: "12345678-1234-1234-1234-123456789012",
        name: "Contoso Corporation",
        domain: "contoso.onmicrosoft.com",
        status: "active",
        lastReport: "2026-01-01"
    },
    {
        id: "2",
        tenantId: "87654321-4321-4321-4321-210987654321",
        name: "Fabrikam Inc",
        domain: "fabrikam.onmicrosoft.com",
        status: "active",
        lastReport: "2025-12-28"
    },
    {
        id: "3",
        tenantId: "11111111-2222-3333-4444-555555555555",
        name: "Adventure Works",
        domain: "adventureworks.onmicrosoft.com",
        status: "pending",
        lastReport: "Never"
    }
];

let selectedTenant = null;

// Load and display tenants
function loadTenants() {
    const tenantsList = document.getElementById('tenantsList');
    
    if (tenants.length === 0) {
        tenantsList.innerHTML = '<p style="text-align: center; color: #666; padding: 20px;">No tenants found. Click "Add Tenant" to get started.</p>';
        return;
    }
    
    tenantsList.innerHTML = '';
    
    tenants.forEach(tenant => {
        const tenantItem = createTenantElement(tenant);
        tenantsList.appendChild(tenantItem);
    });
}

function createTenantElement(tenant) {
    const div = document.createElement('div');
    div.className = 'tenant-item';
    div.dataset.tenantId = tenant.id;
    
    const statusClass = tenant.status === 'active' ? 'active' : 
                       tenant.status === 'pending' ? 'pending' : 'inactive';
    
    div.innerHTML = `
        <div class="tenant-name">${tenant.name}</div>
        <div class="tenant-domain">${tenant.domain}</div>
        <div class="tenant-meta">
            <span class="status-badge ${statusClass}">${tenant.status}</span>
            <span>Last report: ${tenant.lastReport}</span>
        </div>
    `;
    
    div.addEventListener('click', () => selectTenant(tenant.id));
    
    return div;
}

function selectTenant(tenantId) {
    const tenant = tenants.find(t => t.id === tenantId);
    if (!tenant) return;
    
    selectedTenant = tenant;
    
    // Update UI
    document.querySelectorAll('.tenant-item').forEach(item => {
        item.classList.remove('selected');
    });
    
    document.querySelector(`[data-tenant-id="${tenantId}"]`).classList.add('selected');
    
    // Show tenant details
    showTenantDetails(tenant);
}

function showTenantDetails(tenant) {
    const detailsPanel = document.getElementById('tenantDetails');
    
    document.getElementById('selectedTenantName').textContent = tenant.name;
    document.getElementById('detailTenantId').textContent = tenant.tenantId;
    document.getElementById('detailDomain').textContent = tenant.domain;
    
    const statusBadge = document.getElementById('detailStatus');
    const statusClass = tenant.status === 'active' ? 'active' : 
                       tenant.status === 'pending' ? 'pending' : 'inactive';
    statusBadge.className = 'status-badge ' + statusClass;
    statusBadge.textContent = tenant.status;
    
    document.getElementById('detailLastReport').textContent = tenant.lastReport;
    
    detailsPanel.style.display = 'block';
}

// Search functionality
function filterTenants(searchTerm) {
    const filteredTenants = tenants.filter(tenant => 
        tenant.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        tenant.domain.toLowerCase().includes(searchTerm.toLowerCase())
    );
    
    const tenantsList = document.getElementById('tenantsList');
    tenantsList.innerHTML = '';
    
    if (filteredTenants.length === 0) {
        tenantsList.innerHTML = '<p style="text-align: center; color: #666; padding: 20px;">No tenants match your search.</p>';
        return;
    }
    
    filteredTenants.forEach(tenant => {
        const tenantItem = createTenantElement(tenant);
        tenantsList.appendChild(tenantItem);
    });
}

// Action handlers
async function runReport() {
    if (!selectedTenant) return;
    
    try {
        const confirmed = confirm(`Run Cyber Essentials report for ${selectedTenant.name}?`);
        if (!confirmed) return;
        
        // TODO: Replace with actual API call
        // const token = await window.authModule.getAccessToken();
        // const response = await fetch(`${apiConfig.baseUrl}${apiConfig.endpoints.runReport}`, {
        //     method: 'POST',
        //     headers: {
        //         'Authorization': `Bearer ${token}`,
        //         'Content-Type': 'application/json'
        //     },
        //     body: JSON.stringify({ tenantId: selectedTenant.tenantId })
        // });
        
        alert(`Report generation started for ${selectedTenant.name}\n\nThis is a demo. Integrate with your backend API to run actual reports.`);
        
        // Update last report date
        selectedTenant.lastReport = new Date().toISOString().split('T')[0];
        loadTenants();
        showTenantDetails(selectedTenant);
        
    } catch (error) {
        console.error('Run report error:', error);
        alert('Failed to run report: ' + error.message);
    }
}

async function reconsentTenant() {
    if (!selectedTenant) return;
    
    try {
        const confirmed = confirm(`Initiate reconsent process for ${selectedTenant.name}?\n\nThis will redirect you to the Microsoft consent page.`);
        if (!confirmed) return;
        
        // TODO: Replace with actual reconsent flow
        // This would typically redirect to Azure AD consent endpoint
        // const consentUrl = `https://login.microsoftonline.com/${selectedTenant.tenantId}/adminconsent?client_id=${msalConfig.auth.clientId}`;
        // window.location.href = consentUrl;
        
        alert(`Reconsent initiated for ${selectedTenant.name}\n\nThis is a demo. Integrate with your actual consent flow.`);
        
    } catch (error) {
        console.error('Reconsent error:', error);
        alert('Failed to initiate reconsent: ' + error.message);
    }
}

async function removeTenant() {
    if (!selectedTenant) return;
    
    try {
        const confirmed = confirm(`Are you sure you want to remove ${selectedTenant.name}?\n\nThis action cannot be undone.`);
        if (!confirmed) return;
        
        // TODO: Replace with actual API call
        // const token = await window.authModule.getAccessToken();
        // const response = await fetch(`${apiConfig.baseUrl}${apiConfig.endpoints.removeTenant}/${selectedTenant.id}`, {
        //     method: 'DELETE',
        //     headers: {
        //         'Authorization': `Bearer ${token}`
        //     }
        // });
        
        // Remove from local array
        tenants = tenants.filter(t => t.id !== selectedTenant.id);
        
        alert(`${selectedTenant.name} has been removed.`);
        
        // Reset UI
        selectedTenant = null;
        document.getElementById('tenantDetails').style.display = 'none';
        loadTenants();
        
    } catch (error) {
        console.error('Remove tenant error:', error);
        alert('Failed to remove tenant: ' + error.message);
    }
}

function addTenant() {
    const name = document.getElementById('tenantName').value.trim();
    const tenantId = document.getElementById('tenantId').value.trim();
    const domain = document.getElementById('tenantDomain').value.trim();
    
    if (!name || !tenantId || !domain) {
        alert('Please fill in all fields');
        return;
    }
    
    // Validate GUID format
    const guidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!guidRegex.test(tenantId)) {
        alert('Please enter a valid Tenant ID (GUID format)');
        return;
    }
    
    // TODO: Replace with actual API call
    // const token = await window.authModule.getAccessToken();
    // const response = await fetch(`${apiConfig.baseUrl}${apiConfig.endpoints.tenants}`, {
    //     method: 'POST',
    //     headers: {
    //         'Authorization': `Bearer ${token}`,
    //         'Content-Type': 'application/json'
    //     },
    //     body: JSON.stringify({ name, tenantId, domain })
    // });
    
    const newTenant = {
        id: Date.now().toString(),
        tenantId: tenantId,
        name: name,
        domain: domain,
        status: 'pending',
        lastReport: 'Never'
    };
    
    tenants.push(newTenant);
    
    // Close modal and refresh list
    closeAddTenantModal();
    loadTenants();
    
    alert(`${name} has been added successfully!`);
}

// Modal functions
function openAddTenantModal() {
    document.getElementById('addTenantModal').style.display = 'flex';
}

function closeAddTenantModal() {
    document.getElementById('addTenantModal').style.display = 'none';
    document.getElementById('tenantName').value = '';
    document.getElementById('tenantId').value = '';
    document.getElementById('tenantDomain').value = '';
}

// Event listeners
document.addEventListener('DOMContentLoaded', () => {
    // Search
    const searchInput = document.getElementById('searchTenants');
    if (searchInput) {
        searchInput.addEventListener('input', (e) => {
            filterTenants(e.target.value);
        });
    }
    
    // Add tenant button
    const addTenantButton = document.getElementById('addTenantButton');
    if (addTenantButton) {
        addTenantButton.addEventListener('click', openAddTenantModal);
    }
    
    // Close details button
    const closeDetailsButton = document.getElementById('closeDetailsButton');
    if (closeDetailsButton) {
        closeDetailsButton.addEventListener('click', () => {
            document.getElementById('tenantDetails').style.display = 'none';
            selectedTenant = null;
            document.querySelectorAll('.tenant-item').forEach(item => {
                item.classList.remove('selected');
            });
        });
    }
    
    // Action buttons
    const runReportButton = document.getElementById('runReportButton');
    if (runReportButton) {
        runReportButton.addEventListener('click', runReport);
    }
    
    const reconsentButton = document.getElementById('reconsentButton');
    if (reconsentButton) {
        reconsentButton.addEventListener('click', reconsentTenant);
    }
    
    const removeTenantButton = document.getElementById('removeTenantButton');
    if (removeTenantButton) {
        removeTenantButton.addEventListener('click', removeTenant);
    }
    
    // Modal buttons
    const closeModalButton = document.getElementById('closeModalButton');
    const cancelAddButton = document.getElementById('cancelAddButton');
    if (closeModalButton) {
        closeModalButton.addEventListener('click', closeAddTenantModal);
    }
    if (cancelAddButton) {
        cancelAddButton.addEventListener('click', closeAddTenantModal);
    }
    
    const confirmAddButton = document.getElementById('confirmAddButton');
    if (confirmAddButton) {
        confirmAddButton.addEventListener('click', addTenant);
    }
    
    // Close modal when clicking outside
    const modal = document.getElementById('addTenantModal');
    if (modal) {
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                closeAddTenantModal();
            }
        });
    }
});

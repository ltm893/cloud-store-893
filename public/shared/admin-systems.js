/**
 * Systems status — OCI inventory, repo, LB cert, Node route health.
 */
(function initAdminSystems() {
  const systemsPanelEl = document.getElementById('systemsPanel');
  const refreshBtnEl = document.getElementById('systemsRefreshBtn');
  const generatedAtEl = document.getElementById('systemsGeneratedAt');
  const repoEl = document.getElementById('systemsRepo');
  const buildEl = document.getElementById('systemsBuild');
  const ociResourcesEl = document.getElementById('systemsOciResources');
  const certEl = document.getElementById('systemsCert');
  const routesEl = document.getElementById('systemsRoutes');
  const clientsEl = document.getElementById('systemsClients');
  const overviewEl = document.getElementById('systemsOverview');
  const hostEl = document.getElementById('systemsHost');

  let apiFetch = null;
  let setStatus = null;
  let active = false;

  function statusClass(status) {
    if (status === 'ok') return 'systems-ok';
    if (status === 'warning') return 'systems-warning';
    if (status === 'fail' || status === 'expired') return 'systems-fail';
    return 'systems-muted';
  }

  function statusDot(status) {
    return `<span class="systems-dot ${statusClass(status)}" aria-hidden="true"></span>`;
  }

  function formatTimestamp(value) {
    if (!value) return '—';
    return String(value).replace('T', ' ').replace('Z', ' UTC');
  }

  function renderOciResources(oci) {
    if (!ociResourcesEl) return;
    const rows = Array.isArray(oci?.resources) ? oci.resources : [];
    const metaParts = [
      oci?.compartment ? `Compartment: ${oci.compartment}` : null,
      oci?.region ? `Region: ${oci.region}` : null,
      oci?.source ? `Source: ${oci.source}` : null,
      oci?.generatedAt ? `Manifest: ${formatTimestamp(oci.generatedAt)}` : null,
    ].filter(Boolean);
    const metaHtml = metaParts.length
      ? `<p class="hint systems-oci-meta">${escapeHtml(metaParts.join(' · '))}</p>`
      : '';

    if (!rows.length) {
      ociResourcesEl.innerHTML = `<div class="systems-oci-resources-card">
        <h2 class="systems-card-title">OCI resources</h2>
        ${metaHtml}
        <p class="hint">No OCI resources in manifest. Run <code>./scripts/oci/sync-systems-manifest.sh</code> before deploy.</p>
      </div>`;
      return;
    }
    const list = rows
      .map(
        (row) => `<article class="systems-oci-card">
          <div class="systems-oci-card-head">
            <span class="systems-oci-type">${escapeHtml(row.type || '—')}</span>
            <span class="systems-oci-name">${escapeHtml(row.name || '—')}</span>
            <span class="systems-oci-state">${escapeHtml(row.state || '—')}</span>
          </div>
          <div class="systems-oci-id">${escapeHtml(row.id || '—')}</div>
        </article>`,
      )
      .join('');
    ociResourcesEl.innerHTML = `<div class="systems-oci-resources-card">
      <h2 class="systems-card-title">OCI resources</h2>
      ${metaHtml}
      <div class="systems-oci-cards">${list}</div>
    </div>`;
  }

  function renderCertField(label, valueHtml) {
    return `<div class="systems-cert-field">
      <dt>${escapeHtml(label)}</dt>
      <dd>${valueHtml}</dd>
    </div>`;
  }

  function wrapLbCertCard(bodyHtml) {
    return `<div class="systems-lb-cert-card">
      <h2 class="systems-card-title">Load balancer certificate</h2>
      <div class="systems-cert-body">${bodyHtml}</div>
    </div>`;
  }

  function renderCert(cert) {
    if (!certEl) return;
    const fields = [];

    if (cert?.hostname) {
      fields.push(renderCertField('TLS hostname', `<span class="systems-ocid">${escapeHtml(cert.hostname)}</span>`));
    }
    if (cert?.lbPublicIp) {
      fields.push(renderCertField('LB public IP', escapeHtml(cert.lbPublicIp)));
    }
    if (cert?.lbOcid) {
      fields.push(renderCertField('LB OCID', `<span class="systems-ocid">${escapeHtml(cert.lbOcid)}</span>`));
    }
    if (cert?.certName) {
      fields.push(renderCertField('Certificate name', escapeHtml(cert.certName)));
    }
    if (cert?.certOcid) {
      fields.push(renderCertField('Certificate OCID', `<span class="systems-ocid">${escapeHtml(cert.certOcid)}</span>`));
    }

    if (cert?.skipped) {
      certEl.innerHTML = wrapLbCertCard(
        `${fields.join('')}<p class="hint systems-cert-note">${escapeHtml(cert.reason || 'TLS check skipped')}</p>`,
      );
      return;
    }
    if (!cert?.ok) {
      certEl.innerHTML = wrapLbCertCard(
        `${fields.join('')}<p class="systems-fail systems-cert-note">${statusDot('fail')} Could not read certificate: ${escapeHtml(cert?.error || 'unknown error')}</p>`,
      );
      return;
    }

    const days = cert.daysRemaining == null ? '—' : `${cert.daysRemaining} day(s)`;
    const probeNote =
      cert.probeHost && cert.probeHost !== cert.hostname
        ? ` <span class="hint">(via ${escapeHtml(cert.probeHost)})</span>`
        : '';

    fields.push(renderCertField('Host', `${escapeHtml(cert.hostname || '—')}${probeNote}`));
    fields.push(renderCertField('Subject', escapeHtml(cert.name || '—')));
    fields.push(renderCertField('Issuer', escapeHtml(cert.issuer || '—')));
    fields.push(
      renderCertField(
        'Expires',
        `<span class="${statusClass(cert.status)}">${statusDot(cert.status)} ${formatTimestamp(cert.expiresAt)} (${escapeHtml(days)})</span>`,
      ),
    );

    certEl.innerHTML = wrapLbCertCard(fields.join(''));
  }

  function renderRoutes(routes) {
    if (!routesEl) return;
    const rows = Array.isArray(routes) ? routes : [];
    const hint =
      '<p class="hint systems-routes-hint">Green = expected response; red = unexpected or unreachable.</p>';
    if (!rows.length) {
      routesEl.innerHTML = `<div class="systems-routes-card">
        <h2 class="systems-card-title">Node route health</h2>
        ${hint}
        <p class="hint">No route checks configured.</p>
      </div>`;
      return;
    }
    const list = rows
      .map((row) => {
        const status = row.ok ? 'ok' : 'fail';
        const detail = row.error
          ? escapeHtml(row.error)
          : `HTTP ${row.statusCode} (expected ${(row.expected || []).join(' or ')})`;
        return `<div class="systems-route-row ${statusClass(status)}" role="status">
          <div class="systems-route-main">
            <code class="systems-route-path">${escapeHtml(row.route || '—')}</code>
            <span class="systems-route-label">${escapeHtml(row.label || '—')}</span>
          </div>
          <div class="systems-route-result">${detail}</div>
        </div>`;
      })
      .join('');
    routesEl.innerHTML = `<div class="systems-routes-card">
      <h2 class="systems-card-title">Node route health</h2>
      ${hint}
      <div class="systems-routes-list">${list}</div>
    </div>`;
  }

  function renderRepo(repo) {
    if (!repoEl) return;
    const url = repo?.url;
    const label = repo?.label || url || '—';
    if (!url) {
      repoEl.innerHTML = '';
      repoEl.textContent = '—';
      return;
    }
    repoEl.innerHTML = `<div class="systems-repo-card">
      <h2 class="systems-card-title">Code Repository</h2>
      <p class="systems-repo-link">
        <a href="${escapeHtml(url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(label)}</a>
      </p>
    </div>`;
  }

  function renderHost(host) {
    if (!hostEl) return;
    const title = host?.host?.title || 'Host OCI';
    const fields = Array.isArray(host?.host?.fields) ? host.host.fields : [];
    if (overviewEl) {
      overviewEl.textContent = host?.overview || '';
    }
    if (!fields.length) {
      hostEl.innerHTML = '';
      return;
    }
    hostEl.innerHTML = `<div class="systems-host-card">
      <h2 class="systems-card-title">${escapeHtml(title)}</h2>
      ${fields
        .map(
          (field) => `<div class="systems-cert-field">
          <dt>${escapeHtml(field.label || '—')}</dt>
          <dd>${escapeHtml(field.value || '—')}</dd>
        </div>`,
        )
        .join('')}
    </div>`;
  }

  function renderClients(clients) {
    if (!clientsEl) return;
    const groups = clients && typeof clients === 'object' ? Object.values(clients) : [];
    if (!groups.length) {
      clientsEl.innerHTML = `<div class="systems-display-devices-card">
        <h2 class="systems-card-title">Store clients</h2>
        <p class="hint">No client catalog configured.</p>
      </div>`;
      return;
    }
    const body = groups
      .map((group) => {
        const cards = (group.clients || [])
          .map((client) => {
            const where = client.path
              ? `<code>${escapeHtml(client.path)}</code>`
              : client.repo
                ? `<code>${escapeHtml(client.repo)}</code>`
                : '';
            return `<article class="systems-client-card">
              <div class="systems-client-card-head">
                <span class="systems-client-name">${escapeHtml(client.name || '—')}</span>
                <span class="systems-client-app">${escapeHtml(client.app || '')}</span>
              </div>
              ${where ? `<p class="systems-client-where">${where}</p>` : ''}
              <p class="systems-client-notes">${escapeHtml(client.notes || '')}</p>
            </article>`;
          })
          .join('');
        return `<section class="systems-client-group">
          <h4>${escapeHtml(group.title || 'Clients')}</h4>
          <p class="hint systems-client-summary">${escapeHtml(group.summary || '')}</p>
          <div class="systems-client-cards">${cards}</div>
        </section>`;
      })
      .join('');
    clientsEl.innerHTML = `<div class="systems-display-devices-card">
      <h2 class="systems-card-title">Store clients</h2>
      <div class="systems-client-groups">${body}</div>
    </div>`;
  }

  function formatBuildLine(build) {
    if (build?.display) return build.display;
    const buildId = build?.buildId;
    const label = build?.label;
    if (!buildId) return '—';
    const left = label || buildId;
    const versionPrefix = build?.appVersion ? `v${build.appVersion} · ` : '';
    const shaSuffix = build?.gitSha ? ` (${build.gitSha})` : '';
    return `${versionPrefix}${left} : ${buildId}${shaSuffix}`;
  }

  function renderBuild(build) {
    if (!buildEl) return;
    if (!build?.buildId) {
      buildEl.innerHTML = '';
      buildEl.textContent = '—';
      return;
    }
    buildEl.innerHTML = `<div class="systems-build-card">
      <h2 class="systems-card-title">Running build</h2>
      <p class="systems-build-line">${escapeHtml(formatBuildLine(build))}</p>
    </div>`;
  }

  function renderSystems(data) {
    if (generatedAtEl) {
      generatedAtEl.textContent = data.generatedAt
        ? formatTimestamp(data.generatedAt)
        : '—';
    }
    renderHost(data.host);
    renderRepo(data.repo);
    if (buildEl) {
      renderBuild(data.build);
    }
    renderClients(data.clients);
    renderOciResources(data.oci);
    renderCert(data.lbCertificate);
    renderRoutes(data.routes);
  }

  async function loadSystems() {
    try {
      setStatus?.('Loading systems status…');
      const fetchFn = apiFetch || ((url) => fetch(url, { credentials: 'same-origin' }));
      const res = await fetchFn('/api/systems');
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Failed to load systems status');
      renderSystems(data);
      setStatus?.('');
    } catch (err) {
      setStatus?.(err.message || 'Failed to load systems status', true);
    }
  }

  function activate() {
    active = true;
    if (systemsPanelEl) systemsPanelEl.hidden = false;
    loadSystems();
  }

  function deactivate() {
    active = false;
    if (systemsPanelEl) systemsPanelEl.hidden = true;
  }

  function configure({ apiFetch: fetchFn, setStatus: statusFn }) {
    apiFetch = fetchFn;
    setStatus = statusFn;
  }

  refreshBtnEl?.addEventListener('click', loadSystems);

  window.AdminSystems = {
    configure,
    activate,
    deactivate,
    loadSystems,
    isActive: () => active,
  };
})();

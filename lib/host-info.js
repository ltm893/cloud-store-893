/** OCI host summary for the Systems tab. */

function getHostInfo() {
  const region = process.env.SYSTEMS_OCI_REGION || null;
  const fields = [
    { label: 'Service', value: 'OCI Container Instance' },
    { label: 'Shape', value: 'CI.Standard.A1.Flex — Ampere ARM (A1)' },
    { label: 'Size', value: '1 OCPU, 6 GB RAM' },
  ];
  if (region) {
    fields.push({ label: 'Region', value: region });
  }

  return {
    overview:
      'Cloud Store 893 at oci.cloudstore893.com is a POS system running in a Node.js container on Oracle Cloud and protected by Oracle Identity Access Management. Cash register clients are available on iPad and Android tablets. The admin interface supports supervisor push notifications, reporting, and table access.',
    host: {
      title: 'Host OCI',
      fields,
    },
  };
}

module.exports = { getHostInfo };

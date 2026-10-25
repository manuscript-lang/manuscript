export default {
  turbopack: {root: process.cwd()},
  async headers() {return [{source: '/:path*', headers: [{key: 'X-Example', value: 'reference'}]}];},
};

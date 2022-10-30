export default ({ env }) => ({
 url: env('APP_URL', 'https://cms.nurulhudaapon.com'),
  port: process.env.PORT,
});

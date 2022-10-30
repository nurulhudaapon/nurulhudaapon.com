const parse = require('pg-connection-string').parse;
console.log('HIHHHHH', process.env)
const config = parse(process.env.DATABASE_URL);

const env = ({ env }) => {
  return {
    connection: {
      client: "postgres",
      connection: {
        host: config.host,
        port: config.port,
        database: config.database,
        user: config.user,
        password: config.password,
        ssl: {
          rejectUnauthorized: false,
        },
      },
      debug: false,
    },
  }
};

export default env;
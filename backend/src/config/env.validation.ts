import * as Joi from 'joi';

const envSchema = Joi.object({
  NODE_ENV: Joi.string()
    .valid('development', 'test', 'production')
    .default('development'),
  PORT: Joi.number().port().default(3000),
  API_PREFIX: Joi.string().default('api'),
  DATABASE_URL: Joi.string().uri({ scheme: ['postgresql', 'postgres'] }),
  DB_HOST: Joi.string(),
  DB_PORT: Joi.number().port().default(5432),
  DB_USERNAME: Joi.string(),
  DB_PASSWORD: Joi.string(),
  DB_NAME: Joi.string(),
  DB_SCHEMA: Joi.string().default('public'),
  JWT_SECRET: Joi.string().min(16).required(),
  JWT_EXPIRES_IN: Joi.string().default('1d'),
  APP_NAME: Joi.string().default('Sistema Solares Backend'),
  PANEL_WEB_ORIGIN: Joi.string().allow('').optional().default(''),
  PANEL_WEB_ORIGINS: Joi.string().allow('').optional().default(''),
  STORAGE_DRIVER: Joi.string().valid('local', 's3', 'r2').default('local'),
  R2_ENDPOINT: Joi.string().uri({ scheme: ['http', 'https'] }),
  R2_BUCKET: Joi.string(),
  READ_ONLY_MODE: Joi.boolean().truthy('true').falsy('false').default(false),
})
  .custom((value, helpers) => {
    const hasDatabaseUrl = typeof value.DATABASE_URL === 'string'
      && value.DATABASE_URL.trim().length > 0;

    if (!hasDatabaseUrl) {
      const requiredDbVariables = ['DB_HOST', 'DB_USERNAME', 'DB_PASSWORD', 'DB_NAME'];
      const missingDbVariables = requiredDbVariables.filter((key) => {
        const currentValue = value[key];
        return typeof currentValue !== 'string' || currentValue.trim().length === 0;
      });

      if (missingDbVariables.length > 0) {
        return helpers.error('any.custom', {
          message: `DATABASE_URL o las variables ${missingDbVariables.join(', ')} son obligatorias.`,
        });
      }
    }

    if ((value.STORAGE_DRIVER === 'r2' || value.STORAGE_DRIVER === 's3')) {
      const missingStorageVariables = ['R2_ENDPOINT', 'R2_BUCKET'].filter((key) => {
        const currentValue = value[key];
        return typeof currentValue !== 'string' || currentValue.trim().length === 0;
      });

      if (missingStorageVariables.length > 0) {
        return helpers.error('any.custom', {
          message: `Para STORAGE_DRIVER=${value.STORAGE_DRIVER} debes definir ${missingStorageVariables.join(', ')}.`,
        });
      }
    }

    return value;
  })
  .messages({
    'any.custom': '{{#message}}',
  });

export const envValidationSchema = envSchema;
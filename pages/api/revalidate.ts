import type { NextApiRequest, NextApiResponse } from 'next';

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  const strapiSingature = req.headers['x-strapi-webhook'] as string
  let isStrapi = false

  const body = await readBody(req) // Read the body into a string
  if (strapiSingature === process.env.STRAPI_WEBHOOK_SECRET || 'just-for-dev-null') {
    isStrapi = true
  }
  else {
    res.status(401).json({ message: 'Invalid signature' })
    return
  }

  const { _id: id, entry = {}, model } = JSON.parse(body);

  try {
    let postSlug, snippetSlug;

    if (model === 'post') postSlug = entry.slug;
    if (model === 'snippet') snippetSlug = entry.slug;


    if (postSlug) await Promise.all([
      res.revalidate('/blog'),
      res.revalidate(`/blog/${postSlug}`)
    ]);

    if (snippetSlug) await Promise.all([
      res.revalidate('/snippets'),
      res.revalidate(`/snippets/${postSlug}`)
    ]);

    return res.status(200).json({ message: `Updated ${postSlug || snippetSlug}` });
  } catch (err) {
    return res.status(500).json({ message: err.message });
  }
}

export const config = {
  api: {
    bodyParser: false
  }
}

async function readBody(readable: NextApiRequest) {
  const chunks = []
  for await (const chunk of readable) {
    chunks.push(typeof chunk === 'string' ? Buffer.from(chunk) : chunk)
  }
  return Buffer.concat(chunks).toString('utf8')
}

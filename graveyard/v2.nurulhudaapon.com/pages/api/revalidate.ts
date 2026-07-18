import type { NextApiRequest, NextApiResponse } from 'next';

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
    try {
        await Promise.all([res.revalidate('/blog')]);

        return res.status(200).json({ message: `Updated blog page` });
    } catch (err) {
        return res.status(500).json({ message: err.message });
    }
}

export const config = {
    api: {
        bodyParser: false,
    },
};
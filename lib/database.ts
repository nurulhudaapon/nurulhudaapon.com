import clientPromise from './mongodb';

export async function getViewCount(contentSlug: string, contentType: string): Promise<number> {
    const client = await clientPromise;
    const collection = client.db('test').collection('views');
    return await collection.countDocuments({ slug: contentSlug, type: contentType });
}

export async function getTotalViewCount(): Promise<number> {
    const client = await clientPromise;
    const collection = client.db('test').collection('views');
    return await collection.countDocuments();
}

export async function getTotalSubscriberCount(): Promise<number> {
    const client = await clientPromise;
    const collection = client.db('test').collection('subscribers');
    return await collection.countDocuments();
}

export async function getSubscriberByEmail(email: string) {
    const client = await clientPromise;
    const collection = client.db('test').collection('subscribers');
    return await collection.findOne({ email });
}

export async function createView(ip: string, contentSlug: string, contentType: string) {
    const client = await clientPromise;
    return await client.db('test').collection('views').insertOne({
        ip,
        type: contentType,
        slug: contentSlug,
        createdAt: new Date()
    });
}

export async function createSubscriber(email: string) {
    const client = await clientPromise;
    return await client.db('test').collection('subscribers').insertOne({
        email,
        createdAt: new Date()
    });
}
import { MongoClient, ObjectId } from 'mongodb';
import { cookies, headers } from 'next/headers';

// MongoDB connection
const uri = process.env.MONGODB_URI;
if (!uri) {
  throw new Error('Please add your MongoDB URI to .env.local');
}

const client = new MongoClient(uri);
let clientPromise: Promise<MongoClient>;

if (process.env.NODE_ENV === 'development') {
  // In development mode, use a global variable so that the value
  // is preserved across module reloads caused by HMR (Hot Module Replacement).
  if (!(global as any)._mongoClientPromise) {
    (global as any)._mongoClientPromise = client.connect();
  }
  clientPromise = (global as any)._mongoClientPromise;
} else {
  // In production mode, it's best to not use a global variable.
  clientPromise = client.connect();
}

export interface Question {
  _id: string;
  question: string;
  answer?: string;
  email?: string;
  createdAt: string;
  visitorId?: string;
  visitor?: any;
}

// Database functions
async function createQuestion(question: string, email: string, visitorId: string, visitor: any) {
  const client = await clientPromise;
  return await client.db('test').collection('questions').insertOne({
    question,
    email,
    createdAt: new Date(),
    visitorId,
    visitor,
  });
}

async function updateQuestion(id: string, answer?: string, deleted?: boolean) {
  const client = await clientPromise;
  const updateData: any = { updatedAt: new Date() };
  if (answer !== undefined) updateData.answer = answer;
  if (deleted !== undefined) updateData.deleted = deleted;

  return await client
    .db('test')
    .collection('questions')
    .updateOne({ _id: new ObjectId(id) }, { $set: updateData });
}

async function getQuestions(visitorId: string) {
  const client = await clientPromise;
  const questions = await client
    .db('test')
    .collection('questions')
    .find({ visitorId })
    .sort({ createdAt: -1 }) // Sort by creation date, newest first
    .toArray();
  return questions.map((question) => ({
    ...question,
    _id: question._id.toString(),
    question: question.question,
    createdAt: question.createdAt.toISOString(),
  }));
}

async function getAllQuestions() {
  const client = await clientPromise;
  return await client
    .db('test')
    .collection('questions')
    .find({ deleted: { $ne: true } })
    .sort({
      answer: 1, // Sort by answer field: null/undefined (unanswered) first, then answered
      createdAt: -1, // Then by creation date, newest first
    })
    .toArray();
}

async function createVisitor(ip: string, details: any) {
  const client = await clientPromise;
  return await client.db('test').collection('visitors').insertOne({
    createdAt: new Date(),
    ip,
    details,
  });
}

// Server-side data fetching functions
export async function getQuestionsForVisitor(adminCredential?: string): Promise<Question[]> {
  try {
    const cookieStore = await cookies();
    const visitorId = cookieStore.get('visitor_id')?.value;

    // If admin credential is provided, validate and return all questions
    if (adminCredential) {
      const adminCredentialEnv = process.env.ADMIN_CREDENTIAL;
      if (!adminCredentialEnv || adminCredential !== adminCredentialEnv) {
        throw new Error('Invalid admin credential');
      }
      const questions = await getAllQuestions();
      return questions.map((question) => ({
        ...question,
        _id: question._id.toString(),
        question: question.question,
        createdAt: question.createdAt.toISOString(),
      }));
    }

    // If no visitor ID, return empty array
    if (!visitorId) {
      return [];
    }

    return await getQuestions(visitorId);
  } catch (error) {
    console.error('Error fetching questions:', error);
    return [];
  }
}

export async function submitQuestionServerAction(
  question: string,
  email?: string,
  visitor?: any,
): Promise<{ success: boolean; message: string }> {
  try {
    if (!question) {
      return { success: false, message: 'Question is required' };
    }

    const cookieStore = await cookies();
    const headersList = await headers();

    // Get visitor ID from cookie
    let visitorId = cookieStore.get('visitor_id')?.value;

    // Get client IP
    const forwardedFor = headersList.get('x-forwarded-for');
    const realIp = headersList.get('x-real-ip');
    const clientIp = forwardedFor?.split(',')[0] || realIp || 'unknown';

    // Get user agent
    const userAgent = headersList.get('user-agent') || 'unknown';

    visitor = visitor || {
      ip: clientIp,
      userAgent,
      timestamp: new Date().toISOString(),
    };

    // Create visitor if not exists
    if (!visitorId) {
      const createdVisitor = await createVisitor(clientIp, visitor);
      visitorId = createdVisitor.insertedId.toString();

      // Set the visitor ID as a cookie for future requests
      cookieStore.set('visitor_id', visitorId, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'lax',
        maxAge: 60 * 60 * 24 * 365, // 1 year
      });
    }

    await createQuestion(question, email || '', visitorId, visitor);

    return { success: true, message: 'Your question has been submitted!' };
  } catch (error) {
    console.error('Error submitting question:', error);
    return { success: false, message: 'Oops! Something went wrong. 😔' };
  }
}

export async function updateQuestionAnswerServerAction(
  id: string,
  answer: string,
): Promise<{ success: boolean; message: string }> {
  try {
    if (!answer) {
      return { success: false, message: 'Answer is required' };
    }

    await updateQuestion(id, answer);
    return { success: true, message: 'Your answer has been submitted!' };
  } catch (error) {
    console.error('Error updating question:', error);
    return { success: false, message: 'Oops! Something went wrong. 😔' };
  }
}

export async function deleteQuestionServerAction(id: string): Promise<{ success: boolean }> {
  try {
    await updateQuestion(id, undefined, true);
    return { success: true };
  } catch (error) {
    console.error('Error deleting question:', error);
    return { success: false };
  }
}

import { MDXRemoteSerializeResult } from 'next-mdx-remote';



export type Post = {
  publishedAt: string | number | Date;
  imageUrl: any;
  createdAt: string | number | Date;
  _id: string;
  slug: string;
  content: MDXRemoteSerializeResult;
  title: string;
  date: string;
  excerpt: string;
  coverImage: string;
  readingTime: string;
  tweets: any[];
};

export interface StrapiResponse<T> {
  data: Array<{
    attributes: T;
  }>;
  attributes: T
}

export type Snippet = {
  _id: string;
  slug: string;
  content: MDXRemoteSerializeResult;
  title: string;
  description: string;
  logo: string;
  visibility?: 'unlisted' | 'private';
  priority?: 'high' | 'medium' | 'low';
};

export enum Form {
  Initial,
  Loading,
  Success,
  Already,
  Error
}

export type FormState = {
  state: Form;
  message?: string;
};

export type Subscribers = {
  count: number;
};

export type Views = {
  total: number;
};

export type YouTube = {
  subscriberCount: number;
  viewCount: number;
};

export type GitHub = {
  stars: number;
  followers: number;
};

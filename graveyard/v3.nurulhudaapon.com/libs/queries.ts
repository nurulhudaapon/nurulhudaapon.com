const gql = String.raw;
export const subscribeToNewsletter = gql`
  mutation SubscribeToNewsletter($email: String!) {
    subscribeToNewsletter(input: { email: $email, publicationId: "666d4f03c8a425332693a535" }) {
      status
    }
  }
`;

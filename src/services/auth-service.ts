export interface AuthCredentials {
  email: string;
  password: string;
}

export interface AuthService {
  signIn(credentials: AuthCredentials): Promise<void>;
  createAccount(credentials: AuthCredentials & { name: string }): Promise<void>;
  signOut(): Promise<void>;
}

// A Supabase-backed implementation will be added in the authentication milestone.

// 账号 Service：GET /accounts
import { Account } from '../models/Models';
import { CFApiClient, apiClient } from '../core/network/CFApiClient';

export class AccountService {
  private client: CFApiClient;

  constructor(client: CFApiClient = apiClient) {
    this.client = client;
  }

  fetchAccounts(): Promise<Account[]> {
    return this.client.getList<Account>('/accounts');
  }
}

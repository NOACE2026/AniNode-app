import 'dart:convert';
import 'dart:typed_data';

void main() {
  final tobeparsed = "nEGo+Q6VCN8sZjitDfOWH4uuM1CaJE3o9nVOY0OOeHfETCt1lNQNkf20nxGrrrZKeWyHaZJZbzPP2rhv0XE48QnxxiIUFH7n0FspiHZS69m8GmzVX0c8BcZbwzlgMMbPDST9tay++iSwES0teA2aj204hTTC6MuT3b8V6BXQEpzMnPjABvGfOOYUsMfbgjJTgN470xIamsnUCxWfNdctNwN24KFFs9QELgEiVQTQJuBo3EdUupXfZRGuXO+FXuJi3Hqk5AqaYdguPXp9j6eK4/4/Hc7LnywdNSq4L5McFRLONwH2Ri5oEKmwOb6X0x2/AIuT2gDDNpZTXMinb6XhoRFzWbSNoR32Y6Xmbpl8XxviemKhZ8jQae/e3K70PVCBOlAYDAY/9C5ITll1F9KkFWy+zAK3XW9ygodVLQVlxGK8Ipmri3lO+r7gzDPlN41cq3xONbSSfW4vYUhdu1qn2hKFFheiKFNiZAgMgRPL4o0bHcEgjxNsKPlI9HNsv/StmS+Wb7H8uwwtD5OubcIdMnE7/x/Zq5ddD4h3iJ1JtGOsbagc3rKWNwJ+hyaGs8Guu++JpTmYk9fde1vtdlwjNDiXKV1PZr1OUMlIkkVrWnZAJIT+/aet8yka3bjnv9mgLdyyjV+4HsCi6Cjxl2awK+6jy5fv3VmBbRio4P+jyjZfvW+4GfBpSd6/wwVa0aSYTmXAd1NzGWXbAD4Z+4mHVTlSN3O4mhI4IAGRjfqCo3yciMOq3LbpalLQ+wr0aBbqf+iVjXBnvxPShQa9xLkZd24UrPq81fW908gOZEuXy9TX1TpmER/YRYauC10MedUo5GUiqXkuTKSn201ZVTOv3jPKXEcpaLSsRVqFfoGyDiw2vEbQ9bBql5fI7FvC6KEpeQK1no/YudJBl/bhfbm1y8ZGlNC5/ZZiduwu8qnuDyO7Hr5GNEOaqdj/LX2tGKvyT5xKw0bgKoRkKK1RuhC1GOC6iP9G8HDRLtc4I8mwSLBxG8LzVfvTIC14Xg5DCO0/XDIS+3NuPd0x7ye6s8MaQs8b4tBdAbH0MJ7IUWTK8Bba8jR9Z0giVblONX30KPc0KR5oS4dv+RQU2Y1CjciIATiHOzk1o1xGHPYEpKHa5TD7iIC9IuUvV7wR+5qs6ZFLVBLShymLmyQLPL7y21IHqhpz/TajWK9xm4HaFGqUe0J6tYd8d87OUHEgNED9WIFW1G4NYC7lqc4VmxjJR8eLe1JwB31HOK1E0pzZNL+dZQ2RdyG64cf5KReSJCx7yvrX09DbLPOYRV+PhHZSU+OTRbQEXUM/KgAFAYn3HnSiM4l44/CIlk6XFKJR2rTGTnXw88M6EWEfuPKVkfr1cDyA0uCrYIgf7QK8Ds47bue9DT9z4pJocXe6k30/ujv7S47agPwCinJniJvBZJMpaLqkJePIhB8IzvRTJVM/+pNF+6TjKC3K3NQbBfK2U2MRJob2rlxi7pQYHwKzmGgGlO5yduUFGTyzCAk/htceh2LYnM+v+qtjHqCnCmuHu7ubvXvTz6wGPp1DOHULDTIclWs7EkdLqJE6Fqv1RuEiFCPQP4V7g05C4lmABlPvcFYTczYu1yKff4CSvo0eM2PdysnBfUXzasREFP+THyJpwsIypf9vqXQFZVSevjJNUc/Iv09h/wzr6PT9D0JWu80xvj6839Anqb5gXQVaaaNWOv4zVDqmXjwK/Dl32+++nJR1J4YqcoGdJEpKtTSL4xaQcs9370eWhmGYpM5gKAuJCEc0BzZZMVA3Hgc4CMnMi0+bEYK19q2P3Z4CLHU793t1YUVmQ2o2tw/mSLMlCobWtROq5GNYG3ZHOvL7wUTyGEp5v6UTbyF7aLgCEkfQVW+hSFIMLlXbJKjPZbkLCFATj7HToE22cnpVmIRrbcWV/yw8qrgQNvjKTWh/9QCjPjrc0RAD4lJvObDKn3TblpvS/cmipH1RDbGxZ7XieARsLGbdcIN9UIcfCiMCXvIa9vIusnXHi72xF2Mx88lmbcSwelsCk/blwX4mL6AoK5HNkPA2URP+MGIRFMsFqMt9YUGPQSnMOT4YXIyi70XB6G58L1VOdivRFLWjUtSmnwfidMbPQ2Q6AOrfPJyQihGvAvl7c2sYLfcb8Qg+YjlLL2G7d0fZP01oqqFMylgkTvNd1gcwzvkvVvKziDRM2UGhJ3HZJtlRSl7J2F6hF69C384Oqwet9jp/sf9s7a+rhNrArsLVQMRDiO7eHcmIgrtPoAxpz1OocvmTr_";
  
  try {
    // 1. Decode Base64
    // Base64 padding might be needed if truncated
    String normalized = tobeparsed.replaceAll('_', '/').replaceAll('-', '+');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    
    final bytes = base64.decode(normalized);
    
    // 2. XOR with 56
    final decrypted = bytes.map((b) => b ^ 56).toList();
    
    // 3. Convert to string
    final result = String.fromCharCodes(decrypted);
    print('DECRYPTED: $result');
  } catch (e) {
    print('ERROR: $e');
  }
}
